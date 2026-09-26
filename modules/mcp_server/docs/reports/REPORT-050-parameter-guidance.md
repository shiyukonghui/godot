# REPORT-050 — 每个 `-32602` 都带参数引导（O-1 / N-7），以及「本构建没有这门语言」的诚实回答（N-2）

> **角色**：TASK-050 执行者。任务书 `docs/tasks/TASK-050-parameter-guidance.md`，手册
> `docs/tasks/PLAYBOOK-group-port.md`，证据原文 `docs/reports/REPORT-AUDIT-RACING-BACKLOG.md`
> （O-1 confirmed / N-7 成立 / N-2 成立）。
> **本报告不采信审计报告的结论**：三件事都在本锚点用**自己的**请求、响应与 doctest 重新测了一遍，
> 红相位测的是**改动前**的二进制、绿相位测的是 `build_local.cmd -Force` 重建的二进制（§2）。
> 审计的原始锚点是 `5ee2c596a`，本任务的**开工锚点**是 `889466b85`（提交锚点见 §11；D86：结论一律标锚点）。

---

## 0. 锚点、工件与纪律自证

### 0.1 锚点与构建（D86）

| 项 | 值 | 来源 |
|---|---|---|
| 仓库 / 分支 | `F:\RustProjects\godot-mcp-pro\code\godot` / `feature/mcp-server-module` | `git rev-parse --abbrev-ref HEAD`【实测】 |
| **开工 HEAD** | `889466b85cd462fd24444d6d7ab53efbe0a44d6e`（短 `889466b85`） | `git rev-parse HEAD`【实测】 |
| 开工前工作树 | 只有 4 个既有未跟踪项（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`），无改动 | `git status --porcelain`【实测】 |
| 构建命令 | `modules\mcp_server\scripts\build_local.cmd -Force`（**从 cmd 启动**，`tests=yes`，`module_mono_enabled=no`）→ **exit 0** | `%TEMP%\mcp_server_build_local.log`【实测】 |
| 引擎自报 | `4.8.dev.custom_build.889466b85`（**== 短 HEAD**） | `bin\godot.windows.editor.x86_64.console.exe --version`【实测】 |
| 契约（**改前**） | `docs/tools_list.renamed.json` **118 032 B / sha256 `443f1df2e9a3c5b0a2ad1c4ce532a4cfb6f33d22d0401a02448a0ca0bede914f`**，171 条，`_meta.generator_version=1.11.0`，overrides **23** | 【实测】 |
| 契约（**改后**） | 同上文件 **119 598 B / sha256 `713d486a86e6d887225e3f45abf459eed3976195fa0bcee1760637a7a5424ae4`**，171 条，`_meta.generator_version=1.12.0`，overrides **24** | `python scripts\gen_renamed_contract.py`【实测】 |
| 红/绿相位 | **红 = `889466b85` 的改前二进制**（`git stash` 掉三份实现文件后重建，随后恢复）；**绿 = 同一 HEAD 重建** | §2 |
| **本次所有门用的二进制** | 全部由**同一棵源码树**构建（= 实现提交 `b8b6553d9` 的树）；版本串只是构建时的 git revision：<br>• `4.8.dev.custom_build.889466b85` —— `build_local.cmd -Force` 在**未提交的改动树**上构建（此时 HEAD 还是 `889466b85`）：门①、门②、门⑥c、`individual`/`capture`/`batteries` 三段回归、红相位；<br>• `…b8b6553d9`（实现提交后普通重建）→ 门③④复跑；<br>• `…a95c0bf1e8`（报告提交后普通重建）→ 门③④复跑（§0.1 的复验记录）；<br>• `…bef296415`（勘误提交后普通重建）→ 门③④复跑，**`--version` == 最终 HEAD**。<br>`git diff --name-only b8b6553d9 HEAD` 不含任何 `.cpp`/`.h`，所以四个二进制是**同一份源码**；逐项数字见 `docs/reports/evidence/task050/green/gate-anchors.txt` | 【实测】 |
| 提交锚点 | 见 §11 | `git log` |

> **关于 `--version == HEAD`（写清，避免误读）**：Godot 把 git revision **在构建时**烘进版本串，因此「先构建、后提交」时
> 版本串必然指向**父**提交。本批的处理方式是：
> ① 红/绿与全部门先用 `build_local.cmd -Force` 在改动树上构建（此时 HEAD 还是 `889466b85`，版本串即 `889466b85`）；
> ② 实现提交 `b8b6553d9` **之后**做一次普通重建，版本串变成 `b8b6553d9` → **`--version` == HEAD**，
> 并在这个二进制上**复跑门③ 与门④**（数字完全相同：`301/22367`、`1727/446649`，见 `gate-anchors.txt`）；
> ③ 本报告与证据的提交**只含 `docs/**`**（`git diff --name-only b8b6553d9 a95c0bf1e8` 里没有任何 `.cpp`/`.h`），
> 即该提交的**源码树**就是被验证的那个构建；报告提交之后再做最后一次普通重建并复验 `--version == <报告提交>`。
>
> **已复验（实测，不是承诺）**：报告提交 `a95c0bf1e8` 之后执行 `build_local.cmd`（普通重建，`tests=yes`）→
> 引擎自报 **`4.8.dev.custom_build.a95c0bf1e` == 短 HEAD `a95c0bf1e`**；并在该二进制上复跑门③与门④：
> `301 \| 301 passed \| 0 failed` / `22367 assertions`、`1727 \| 1727 passed \| 0 failed \| 3 skipped` / `446649 assertions`，
> 两者 `exit 0`（日志 `%TEMP%\mcp050\final_gate3.log` sha256 `f3325fa333ce2ca68b61505042998ca15517141e4a52a414dc40bf8ff3053c74`、
> `final_gate4.log` sha256 `71971f53d2d6bbce8b248f884c752fd7d608bdd6a8d22ee2e466cf1fb8fc6a89`）。

### 0.2 端口与进程纪律

* **9877 全程只观测、从不绑定**：两次证据批（red/green）都包在模块统一的端口守卫
  （`scripts\mcp_port_guard.ps1`）里，判定由「本次运行自己拉起的 pid + 命令行」推出：
  `port_9877_pass=True classification=environment_fact_no_listener_before_or_after`
  （本机 9877 本来就没有监听者；`pid_before == pid_after == -1`）。
* **只用 9888（编辑器）/ 9889（游戏）**，一次一个引擎；`--test` 进程不监听端口
  （自报 `[MCP] SceneTree never became available; MCP server disabled`）。
* 没有杀、重启或占用任何**不是本次运行拉起**的进程；运行结束后 `Get-CimInstance … godot*` 为空【实测】。
* **禁止 push**：本批只有本地提交，`git log origin/…` 未动。

### 0.3 证据与脚本纪律

| 纪律 | 实测 |
|---|---|
| 响应体一律 `curl.exe -s -o <file>` 落盘 | 29 个探针 ×2 批，逐个给 `request_sha256` / `response_sha256` / `response_bytes`（`task050/{red,green}/summary.json`） |
| 请求体无 BOM | 全部经 `Write-McpUtf8NoBom`（`mcp_import_guard.ps1`） |
| `.ps1` 纯 ASCII | **4 个**新/改脚本逐字节校验：`non-ascii bytes = 0`（`mcp050_parameter_guidance_evidence.ps1`、`mcp050_regression_battery.ps1`、`mcp043_gates.ps1`、`mcp050_contract_diff.py`） |
| 构建串行、不抑制输出 | 只有 `build_local.cmd` 调 scons，输出全量在 `%TEMP%\mcp_server_build_local.log` |
| 临时文件 | `%TEMP%\mcp050\**`；**关键证据已复制进仓库**（下述 `docs/reports/evidence/task050/`），不依赖会被清理的 `%TEMP%` |
| 证据入库的形态 | 证据 **152 个文件**（`red` 61 / `green` 91 ＝ 直接 64 + `regression` 19 + `flake-ab` 8），加报告共 **153 个入库文件**，`git status --porcelain --ignored=matching` 之后**没有任何遗漏**；其中 **28 个 `.log` 用 `git add -f` 入库**：仓库的 `.gitignore:308` 忽略 `*.log`（本意是构建日志），但这些是**门的一手输出**（门①的逐条 PASS 行、门③/④的 `test cases:` 汇总行、⑥c 的 `101/101`、抖动那次 `test_image.cpp` 的 `SIGSEGV`），报告 §6 的每个数字都能在它们里面逐字找到；前几批把这类日志留在 `%TEMP%`（审计报告的 N-6 正是为这个提过缺陷），本批选择入库。`.json` 证据沿用既有形态（既有 492 个） |
| 只改 `modules/mcp_server/**` | `git status` 逐行核对；hof-rs **只读**；**未改** `DESIGN-DETAIL.md`、未新建任何竞争性规范/日志文档 |
| 引擎进程清理 | 两个证据批、门①、六段回归全部结束后无残留 godot 进程【实测】 |

### 0.4 纪律自证的一处自身事故（诚实优先）

`mcp050_parameter_guidance_evidence.ps1` 第一次落盘 `summary.json` 时抛
`Argument types do not match`（Windows PowerShell 5.1 在
`$table['probes'] = @(<List[object] of PSCustomObject>)` 上抛的；`$list.ToArray()` 正常）。
**发现方式**是脚本退出码 1 且 summary 缺失，不是「看起来过了」；修复是把汇总表按成员逐个赋值并用
`.ToArray()`，并在脚本注释里记下这个 5.1 的行为，避免下一个脚本再踩。红相位的 29 组
request/response 文件在两次失败运行里都已正确落盘，只有汇总表受影响，因此**红相位重跑了一次**以拿到完整证据集。

---

## 1. 交付物

| 文件 | 性质 | 说明 |
|---|---|---|
| `tool_registry.cpp` | 实现（核心） | `+411` 行：`data.suggestion` 生成器 + 两个入口的挂点 + 未知工具名 |
| `tools/project_read_files.h` / `.cpp` | 实现 | N-2：三种情形的判定表 + 诚实拒绝 + 注册块描述字面量 |
| `tests/test_mcp_server.h` | 测试 | `+537` 行：4 个新用例（843→断言），1 处旧断言被**加强**（§7.1） |
| `scripts/gen_renamed_contract.py` | 生成器 | v1.12 段落 + `DESCRIPTION_OVERRIDES["validate_script"]`（append）+ `GENERATOR_VERSION` 1.12.0 |
| `docs/tools_list.renamed.json` | 契约（生成物） | 28 行结构化 diff：**1 条 description + `_meta`**（§5.4） |
| `scripts/mcp050_parameter_guidance_evidence.ps1` | 证据脚本（新） | 29 个真实请求 ×2 批 + 跨工具链 + 端口守卫；不写断言，红绿同一把尺子 |
| `scripts/mcp050_contract_diff.py` | 契约 diff 门（新） | 断言本批只动 1 条描述 + `_meta`，且 append-only |
| `scripts/mcp050_regression_battery.ps1` | 回归批次（新） | 三段：`individual` / `capture` / `batteries`，严格串行、逐步记退出码 |
| `scripts/mcp043_gates.ps1` | 回归修复 | TASK-043 契约 diff 的**右侧改为同一锚点对**（§7.3；`mcp043_contract_diff.py` **一字未改**） |
| `docs/reports/evidence/task050/**` | 证据 | 红/绿两套 29×2 个请求/响应 + summary.json + 门①/③/④ 日志 + 回归日志 |

---

## 2. 红 / 绿（TDD）

### 2.1 红相位：先测「改动前」，两把尺子

**（a）线证据 —— 29 个真实请求，打在同一台机器、同一批 scratch 工程上**
（`docs/reports/evidence/task050/red/summary.json`，sha256 `5c060aec6b6c3a73f641e512ec95bcff7c1b7e152786a51fa2f18493f1dd9801`）：

| 探针 | 锚点 `889466b85`（改前） | 缺陷 |
|---|---|---|
| `e03_n2_validate_cs` | `code=0`，`{"error_text":"ERR_PARSE_ERROR","message":"Compilation failed. Check the script for errors.","path":"res://scripts/legit.cs","valid":false}` | **N-2**：本构建没有 C# 后端 → 冒充「编译失败」 |
| `e06/e08/e09/e10/e11/e14/e16`（缺必填，immediate+deferred） | `-32602`，**无 `data`**，响应 **96–100 B** | **O-1**：审计的 93 B 形态复现（本项目里是 96 B，差异来自 `id` 位数与路径长度） |
| `e12/e13/g01–g08`（嵌套/类型/越界） | `-32602`，**无 `data`**，**96–175 B** | **N-7** |
| `e15_unknown_parameter` | `-32602` + `data.suggestion` = `Accepted parameters of project_get_settings: prefix, include_default`，**215 B** | **对照组**：这正是「有建议」的一侧，本批必须**逐字不动** |
| `e17b_batch_own_suggestion` | `-32602` + `data.suggestion` + `data.batch`，582 B | 对照组：已带建议的 `-32602` 必须**不被覆写** |
| `e19_unknown_tool` | `-32601` | 传输层对未知工具名答 `-32601`（`call_tool` 的 `-32602` 分支只在进程内可达） |

**（b）doctest 相位 —— 4 个新用例在旧实现上真跑真失败**
（`docs/reports/evidence/task050/red/gate3_task050_doctest.log`，exit **1**）：

```
[doctest] test cases:   4 |   0 passed |   4 failed | 1726 skipped
[doctest] assertions: 822 | 344 passed | 478 failed |
[doctest] Status: FAILURE!
SCRIPT ERROR: Parse Error: Expected parameter name.
   at: GDScript::reload (gdscript://-9223372004642520126.gd:3)          <- N-2 的现场：用 GDScript 解析 .cs
running_game_move_player_to_target: code=-32000 message=No scene is currently open
150/151 tools refused the empty call with -32602                          <- 扫描发现的状态优先例外（§6.3）
```

红相位里 `.cs` 被 GDScript 解析器拒绝的引擎日志行，是「借用别的语言」这份行为的直接物证。

### 2.2 绿相位

* doctest：`[MCPServer] TASK-050*` → **4 / 4 passed，843 assertions，0 failed**。
* 线证据：29 个请求全部命中设计形态
  （`docs/reports/evidence/task050/green/summary.json`，sha256 `da2418a475b208ef6119106d67110537e75d2cacf47412305c4821b8577a10b2`）。

**响应字节对照（`response_bytes`，红 → 绿）** —— 「该长的地方长、该一样的地方一模一样」：

| 探针 | 红 | 绿 | 判定 |
|---|---|---|---|
| `e06_validate_missing_param` | 96 | **219** | O-1：缺必填从 96 B 变有建议 |
| `e10_missing_required_deferred` | 98 | **245** | O-1：deferred 入口同样 |
| `e12_nested_missing_type` | 106 | **363** | N-7：嵌套路径定位 + 不可导出时说明原因 |
| `g02_missing_required_deferred` | 97 | **365** | 同上（游戏侧，可解析的 item 形态） |
| `e03_n2_validate_cs` | 229（`valid:false`） | **458**（`-32000` + 建议） | N-2：从「假的结论」变成「真的拒绝」 |
| `e15_unknown_parameter` | 215 | **215** | 对照：TASK-032 的建议**逐字节不变** |
| `e17b_batch_own_suggestion` | 582 | **582** | 对照：handler 自己的 `data` 未被覆写 |
| `e07_validate_missing_file` | 207 | **207** | 对照：`-32001` 一字未动 |
| `e04/e05`（合法/坏 `.gd`） | 173 / 230 | 173 / 230 | 对照：真编译语义不变 |
| `e01/e02/e17/e20`（链上的成功调用） | 218/256/130/256 | 同 | 对照：成功响应不变 |
| `e19_unknown_tool` | 102 | 102 | 对照：传输层 `-32601` 不变 |

---

## 3. O-1：缺**必填**参数的 `-32602` 必须带 `data.suggestion`

### 3.1 落点：注册表的两个入口，而不是 ~30 个 handler

`MCPToolRegistry::call_tool()` 与 `MCPToolRegistry::call_deferred_tool()` 是**handler 唯一的两个可达路径**
（传输层 `mcp_jsonrpc.cpp:314/337`、deferred 通道、doctest 全走这里，GDR-19 §17.2），
并且两者手上都有 `MCPToolDef`（即该工具的契约 `inputSchema`）。逐 handler 写要实现 171 遍、并在第一个新工具上腐烂；
放在这里就是**一条适用于所有工具（含未来工具）的规则**。

```
handler / pending_handler 返回
        ↓
_add_invalid_params_suggestion(def, r_error)
        ↓  r_error.code == -32602 且 data 里没有非空 suggestion 时
data["suggestion"] = _invalid_params_suggestion(def, r_error.message)
```

**铁律（任务书 §4）逐条落实**：

| 要求 | 落实 |
|---|---|
| 错误码不得变 | 不动 `r_error.code`；`invalid_params()` 工厂本身仍然 data-free（它不知道工具） |
| 既有消息文本不得变 | 不动 `r_error.message`；`e06` 的 `message` 仍是 `Missing required parameter: path` |
| 只**增补** `data.suggestion` | 已有非空 `suggestion` → **直接返回**（`e15` 215 B、`e17b` 582 B 逐字节不变） |
| 已有 `data`（如 `data.batch`）不得丢 | 以原 Dictionary 为基础再放 `suggestion`（不新建空表覆盖） |
| immediate / deferred 两条入口都要 | 两个函数各一行挂点（`call_tool` 在 handler 之后，`call_deferred_tool` 在 `pending_handler` 之后） |
| 必填参数「省略」与「为空」都要 | §3.3 实测表 |

### 3.2 建议的确定性结构

```
<点名与形态>; Accepted parameters of <tool>: <按该工具 inputSchema 的键序>
```

* 参数名列表来自**该工具注册的 `inputSchema.properties` 的键序**，与 TASK-032 未知参数门用的是**同一个 helper**
  （`_accepted_parameters_of`），因此两者不可能漂移；「无参数工具」仍答 `<tool> accepts no parameters`。
* **顺序口径（必须写清）**：这里用的是**运行时 `inputSchema` 的键序**，也就是 TASK-032 门逐字断言的同一列表；
  对绝大多数工具它与契约文件里的键序相同，**少数手写注册块的键序不同**（实测：
  `project_get_settings` 运行时是 `prefix, include_default`，契约文件里是 `include_default, prefix`）。
  门① 用**规范化（排序）JSON** 比较，所以这个差异是既有的、门看不到的；本批**不**去动 ~30 个注册块的键序
  （任务书明令「不要改 handler」），只把它记在这里。

### 3.3 实测（绿相位原文，两个入口 × 省略/为空 × 必填）

| 场景 | 入口 | `message`（**逐字不变**） | `data.suggestion`（新增） |
|---|---|---|---|
| `project_validate_script{}` | immediate | `Missing required parameter: path` | `Missing required parameter 'path' (a string); Accepted parameters of project_validate_script: path` |
| `editor_set_node_property{property,value}` | immediate | `Missing required parameter: path` | `Missing required parameter 'path' (a string); Accepted parameters of editor_set_node_property: path, property, value` |
| `editor_rename_node{}`（缺两个） | immediate | `Missing required parameter: path` | `Missing required parameter 'path' (a string); Accepted parameters of editor_rename_node: name, path` |
| `editor_simulate_input_sequence{}` | **deferred** | `Missing required parameter: events` | `Missing required parameter 'events' (an array); Accepted parameters of editor_simulate_input_sequence: events, frame_delay` |
| `editor_simulate_input_sequence{events:[]}`（**为空**） | deferred | `Parameter 'events' must not be empty` | `Parameter 'events' accepts an array (required); Accepted parameters of editor_simulate_input_sequence: events, frame_delay` |
| `editor_execute_gdscript{code:""}`（**为空**） | immediate | `Parameter 'code' must not be empty` | `Parameter 'code' accepts a string (required); Accepted parameters of editor_execute_gdscript: code` |
| `running_game_get_autoload_node{}` | immediate（游戏） | `Missing required parameter: name` | `Missing required parameter 'name' (a string); Accepted parameters of running_game_get_autoload_node: name, properties` |
| `running_game_run_test_scenario{steps:[]}`（**为空**） | deferred（游戏） | `Parameter 'steps' must not be empty` | `Parameter 'steps' accepts an array of an object with members {…}, requiring {type} (required); Accepted parameters of running_game_run_test_scenario: scene_path, steps` |

---

## 4. N-7：**任何** `-32602` 都给可接受形态（含嵌套路径）

### 4.1 生成器是 schema 驱动的，不猜词表

`_invalid_params_suggestion(def, message)` 的步骤：

1. **点名**：`_parameter_name_in_message()` 认三种模块自己的拼写
   （`Missing required parameter: X`；`Parameter 'X' …`；batch writer 的 `'X' must be …`），
   并且**把引号后的路径续写接回来**——场景步骤解析器写的是 `Parameter 'steps[0]'.type must be a string`，
   提取结果是 `steps[0].type`（实测 `g06` 正是这一条）。
   若一种都没认出来，退一步用 `_declared_leading_word()`：只在该词**确实被 schema 声明**时才采用
   （选而不用 mode 的 `mode must be one of: replace, add, remove`，实测 `e18` 因此拿到了 `mode` 的形态）。
2. **定位到路径**：`_lookup_schema_path()` 走 `properties` / `items` / `required`，
   `events[0].type`、`steps[0].type`、`nodes[0].type` 都能走到叶子；`events[0].position.x` 亦然。
3. **给可接受形态**：`_schema_form()` = 类型短语（`a string` / `an integer` / `an array of …` /
   `an object with members {a, b}, requiring {c}`）+ `enum`（`, one of: input|wait|assert`）
   + 必填性（`(required)` / `(optional)` / `, optional (default -1)`）。
4. **无法确定性生成的，说明原因**（任务书 §2 的「范围控制」）：
   契约里 `events` 是**裸数组**（没有 `items`），于是不会编造词表，而是直接说清楚：
   `Missing required parameter 'events[0].type': the schema declares 'events' as an array with no item shape,
   so no accepted member value can be derived from it; Accepted parameters of …`（实测 `e12` / `g07`）。
   连参数名都认不出来时：`The refusal comes from <tool>'s own value rule and names no member its
   inputSchema declares; Accepted parameters of <tool>: …` —— **任何分支都不留空**。
5. **上限**：成员/枚举列表最多 12 项，超出显式写 `... (N members in total)`，不让巨型对象把 `data` 撑爆。

### 4.2 实测（节选，绿相位原文）

| `-32602` 类别 | 探针 | `data.suggestion` |
|---|---|---|
| 嵌套 · 契约可解析 | `g04` `steps[0].type='bogus'` | `Parameter 'steps[0].type' accepts a string, one of: input\|wait\|assert (required); …` |
| 嵌套 · 内部对象缺必填 | `g05` `steps[0]` 缺 `type` | `Parameter 'steps[0]' accepts an object with members {action, expected, keycode, node_path, operator, property, seconds, text, type}, requiring {type} (required); …` |
| 嵌套 · 消息把成员写在引号外 | `g06` `steps[0]` 类型错 | `Parameter 'steps[0].type' accepts …`（路径被正确接回） |
| 嵌套 · 裸数组 | `e12`/`g07` `events[0].type` | `…the schema declares 'events' as an array with no item shape…; …` |
| 类型不符（可选参数） | `e14` `prefix:true` | `Parameter 'prefix' accepts a string (optional); …` |
| 类型不符（带默认值） | `project_get_filesystem_tree{max_depth:"deep"}` | `… optional (default -1) …`（doctest 断言） |
| 枚举（handler 自己拒绝） | `e18` `mode:'toggle'` | `Parameter 'mode' accepts a string (optional); Accepted parameters of editor_set_node_selection: focus, inspect, mode, node_path, node_paths` |
| 越界/语义拒绝（认不出名字） | doctest `expect_invalid` 全家 | 非空 + 含工具名（§7.1 的加强断言） |
| **未知工具名**（也是 `-32602`） | 进程内 `project_no_such_tool` | `'project_no_such_tool' is not a tool of this process; call tools/list to get the exact names it serves`（线上该请求由传输层答 `-32601`，实测 `e19`） |

---

## 5. N-2：语言不可用 ≠ 编译失败

### 5.1 缺陷复现（红相位）

非 Mono 构建里 `ScriptServer::get_language_for_extension("cs")` 为 null；旧实现**回退 GDScript**
（旧 `project_read_files.cpp:302-305`），于是合法的 `.cs` 得到
`{"error_text":"ERR_PARSE_ERROR","valid":false,"message":"Compilation failed…"}`，
引擎日志同时打出 `SCRIPT ERROR: Parse Error: … at: GDScript::reload(gdscript://…gd)`（§2.1b）。

### 5.2 决策：**`-32000` + `data.suggestion`，而不是 `valid:null`**（**一次性偏离，必须交代**）

审计的原文建议是「语言未初始化 → 返回 `valid:null` + 明确说明」；任务书 §3 要求「能力感知的诚实回答 +
`data.suggestion`」并且「`valid` 字段语义要写清」。两者只能取一，我取**前者的一半都不取**：

| 选项 | 否决/采纳理由 |
|---|---|
| A. 成功响应 +`valid:null` | **否**。`null` 在 JS/多数客户端里是 falsy，`if (!valid)` 仍会把「没有后端」读成「不合法」——正是 N-2 要消灭的误读；而且 `DESIGN-DETAIL §16-10` 已经就「构建缺少能力」定过同一族规矩：**`-32000` + 建议，不得把空白帧当成功**。 |
| B. **`-32000` + `data.suggestion`** | **采纳**。能力缺失是**状态**不是**结论**（GDR-14 的 `-32000` 语义）；拒绝里**没有** `valid` 字段，所以调用方不可能把它读成 false；`data.suggestion` 给了下一步（用 Mono 构建 / 换 `.gd`）。 |
| C. 保留 GDScript 回退但加一个 `note` | **否**。仍然把别的语言的解析错误当作本文件的结论，只是多了注解。 |

**`valid` 的语义（写进契约描述，§5.3）**：`valid` **只在真的用该文件自身扩展名对应的脚本语言编译过时**才是结论
（`true` = 编译通过；`false` = 编译失败，`error_text` 给 `ERR_*`）；本构建没有该语言后端时**不产生 `valid`**，
而是 `-32000` 拒绝；进程根本没有初始化任何脚本语言时（`--test` 进程）走既有的**结构检查降级分支**，
其 `message` 明说「没有编译」。

### 5.3 判定表（纯函数，可穷举测试）

```
classify_validate_script_mode(languages_initialized, language_found)
  (false, false) -> STRUCTURAL            # 进程没有脚本语言服务：结构检查降级（doc 明说未编译）
  (false, true ) -> STRUCTURAL            # 不可达；真出现也说明没有可用编译器，不借
  (true , false) -> LANGUAGE_UNAVAILABLE  # N-2：本构建没有这门语言的**脚本后端** -> -32000 + 建议
  (true , true ) -> COMPILE               # 文件自身语言的真 reload()
```
`-32000` 的正文与建议（实测 `e03`）：

```
message    : Cannot validate 'res://scripts/legit.cs': this build has no script backend for '.cs',
             so the file was not parsed or compiled
suggestion : The script backend for '.cs' is not part of this build, so no verdict is possible here:
             validate the file in a build that contains that backend (for '.cs' that is a Mono build,
             module_mono_enabled=yes), or validate a '.gd' script with this build
```

### 5.4 契约同步（`DESCRIPTION_OVERRIDES` append + 重生成 + 指纹）

生成器 v1.12 段落 + 一条 `validate_script`（**append**，原文 `验证脚本语法` 逐字在句首）+
`GENERATOR_VERSION` 1.11.0 → **1.12.0**；重生成后 171 条名字集合不变，**结构化 diff 只有**：

```
changed tools = project_validate_script        （只有 description 字段动，键集合未动）
meta keys moved = generator_version, overrides
overrides 23 -> 24                             （新记录 = description/validate_script:append）
map_sha256 未动
```
新增句（535 B UTF-8）写清三件事：`valid` 只是「用**该文件自身**语言编译过」的结论 / 本构建没有该语言时
**不借别的语言、也不给 `valid`**、而是 `-32000` + `data.suggestion` / 无任何语言时的结构检查降级会明说没有编译。
`tools/project_read_files.cpp` 的注册字面量由脚本**从契约文本逐字复制**（`%TEMP%\mcp050\patch_literal.py`），
门① 在 9888 **和** 9889 上逐字验证 `description=True`（§6.1）。

---

## 6. 门（五道 + 门⑥ 三段式）

| 门 | 命令 | 结果 | 关键数字 |
|---|---|---|---|
| ① 契约子集逐字 | `check_contract_subset.ps1 -Group project_read_files` | **exit 0，3/3 PASS** | 编辑器 9888 / 游戏 9889 各 6/6 条 `name/description/inputSchema` **逐字 True**（含 `project_validate_script: description=True`）；`implemented_union=148(编辑器)/69(游戏)`；`guard_user_port_9877` pid 前后 `-1` |
| ② 三类证据 + 端到端链 | `mcp050_parameter_guidance_evidence.ps1 -Label green` | **exit 0，29 个真实请求** | 成功（`e01/e02/e04/e05/e17/e20`）、缺参（`e06/e08/e09/e10/e11/e16/g01/g02/g03`）、底层失败（`e07` `-32001` + 建议）各成组；链见 §6.2；绿 summary sha256 `da2418a4…` |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **exit 0** | `test cases: 301 \| 301 passed \| 0 failed \| 1429 skipped`；`assertions: 22367 \| 22367 passed \| 0 failed`（**REPORT-049 基线 297 / 21484 → +4 / +883，全部来自本批**） |
| ④ 全引擎回归 | `--headless --test` | **exit 0** | `test cases: 1727 \| 1727 passed \| 0 failed \| 3 skipped`；`assertions: 446649 \| 446649 passed \| 0 failed`（**基线 1723 / 445766 → 同 +4 / +883，0 failed 不变，3 skipped 不变**） |
| ⑤ 收口 `accept_m1.ps1` ×2 | 见 §6.4（在 `mcp041/042/043` 门批次内各跑两次） | 见 §6.4 | 两次 PASS 清单一致 |
| ⑥ 收窄点三段 | a `check_narrowing_points.py`；b `--coverage`；c `mcp031_gate6_coverage_probes.ps1` | **三段 exit 0** | a：`scanned : 75 narrowing point(s) in 16 file(s)` / `pinned : 75`；b：`17 declared spelling(s)`，集合内每种拼写都有探针；c：**101/101 checks passed**，`log sha256=a1515e0a465f0c910e34580b4fb66764a81218701b34ad37411a501f059a64d8`（**与 REPORT-049 记录逐字节相同**）。**本批新增收窄点 0 个**；a 段信息性附注仍是 11 条（与 REPORT-048/049 相同，且漂移行全在**本批未触碰**的 `editor_animation_tree_write.cpp` / `editor_input_simulation.cpp` / `editor_write_scene_editor.cpp` / `project_theme_write.cpp`） |
| 契约 diff（本批自备） | `python scripts\mcp050_contract_diff.py <锚点契约> <实况契约> out.json` | **exit 0，problems=0** | `changed tools = project_validate_script`；`meta keys moved = generator_version, overrides`；`overrides 23 -> 24`；append-only；新增句必须含 `valid` / `module_mono_enabled=no` / `-32000` / `data.suggestion` / `--test` 五个事实（少一个就红） |
| 契约静态检查 | `docs\scripts\check_rename_map.py`；`check_tool_groups.py` | 两个 **exit 0 / PASS** | 契约 119 598 B / `713d486a…`；171 条唯一；组清单不变式全 PASS |

### 6.1 门①的逐字面

```
project_validate_script: name=True description=True inputSchema=True   （9888）
project_validate_script: name=True description=True inputSchema=True   （9889）
PASS editor_9888_contract_subset / PASS game_9889_contract_subset / PASS guard_user_port_9877
3/3 checks passed
```

### 6.2 门②的跨工具端到端活证据链

`project_create_script{res://scripts/legit.cs}` → `project_read_script`（**98 B，与请求内容一致**）
→ `project_validate_script`（**N-2 拒绝**）
→ `project_validate_script{legit.gd}`（`valid:true`）→ `project_validate_script{broken.gd}`（`valid:false` + `error_text`）
→ `editor_open_scene{probe.tscn}` → `editor_add_nodes_batch`（**handler 自己的** `-32602`，`data.suggestion` + `data.batch` 全在）
→ `project_read_script`（**链尾读回，`.cs` 仍是被写入的那些字节**）。
一次 N-2 拒绝**没有**改动文件，这一点由链首尾两次读回的响应 sha256 相同证明。

### 6.3 全量扫描：注册表里**每个**「有必填参数」的工具（151 次调用）

新增 doctest 用例对**两个端点的全部列表现场扫描**，对每个声明了必填参数的工具用空参数调用一次：

* `swept = 151`（编辑器 + 游戏两个列表里 `required` 非空的条目数），
* 其中 `refused = 150` 答 `-32602`：**建议非空 + 含工具名 + 以 `Accepted parameters of <tool>: …` 收尾**（逐条断言），
* 唯一例外 `running_game_move_player_to_target`：它的**状态检查排在参数检查之前**，空调用先撞上
  `-32000 No scene is currently open`（GDR-14，自带建议）。这个例外被**写死在用例里**
  （`STATE_FIRST_TOOLS`）并断言「例外数恰好 1」，因此「某个工具不再拒绝缺参」或「新工具把缺参藏在状态后面」
  会让用例变红，而不是让扫描悄悄缩水；
* 扫描**不覆盖**没有必填参数的工具：对它们传入空参数会**真的执行动作**（保存/截图/生成文件），
  那不是 doctest 该做的事（这与 TASK-032 用「未知参数」让扫描零副作用的做法同源）。

### 6.4 回归批次（严格串行、逐条归因）

> 三段批次全部经 `scripts\mcp050_regression_battery.ps1`（一次一个引擎，绝不并发），
> 每步一段日志、一个退出码，摘要落在 `docs/reports/evidence/task050/green/regression/summary-*.txt`。
> 二进制自报 `4.8.dev.custom_build.889466b85` == `git rev-parse HEAD`（摘要首屏即记录）。

**（a）`-Batch individual`**（`summary-individual.txt`）

| 步骤 | 命令 | 退出码 | 关键数字 |
|---|---|---|---|
| `gate6c_coverage_probes` | `mcp031_gate6_coverage_probes.ps1` | **0** | **101/101 checks passed**；`log sha256=a1515e0a465f0c910e34580b4fb66764a81218701b34ad37411a501f059a64d8`（与 REPORT-049 逐字节相同）；`B1b_restored_byte_identical` / `B1b_worktree_clean_of_probes` 通过（探针不留痕） |
| `regress_mcp010_b2_observation` | `mcp010_b2_observation_evidence.ps1` | **0** | 任务书点名的 B2 观测回归 |
| `regress_mcp019_b4` | `mcp019_b4_evidence.ps1` | **0** | 任务书点名的 B4 回归 |
| `regress_mcp027_object_shape_and_paths` | `mcp027_object_shape_and_paths_evidence.ps1` | **0** | 对象形态/稳定路径回归（**本批最相关的一条**：它也读 `-32602`） |
| `regress_mcp044_capture` | `mcp044_capture_evidence.ps1` | **0** | `40/40 checks passed (phase editor)`（与 MILESTONES/REPORT-048 的 40/40 一致） |
| `regress_mcp045_pixel_compare_cost` | `mcp045_pixel_compare_cost.ps1 -Label post` | **0** | `15/15 checks passed` |
| `regress_mcp046_capture_encode_cost` | `mcp046_capture_encode_cost.ps1 -Label post` | **0** | `23/23 checks passed` |
| `regress_mcp044_zero_change`（**试跑，随后移除**） | `mcp044_zero_change.ps1` | 1 | **归因：缺参数**——该脚本的 `pre` 腿要 TASK-044 之前的二进制（§7.4）。它不在可重跑回归集内，已在批次脚本里显式剔除并写清原因，不用替身凑绿 |

**（b）`-Batch capture`**（`summary-capture.txt`，按 `MILESTONES-CLOSURE §4` / `REPORT-048 §7` 的口径；四相 = 62/62）

| 步骤 | 命令 | 退出码 | 关键数字 |
|---|---|---|---|
| `regress_mcp044_capture_editor` | `mcp044_capture_evidence.ps1 -Phase editor` | **0** | `40/40 checks passed (phase editor)` |
| `regress_mcp044_capture_headless` | `… -Phase headless` | **0** | 8/8（能力判定相） |
| `regress_mcp044_capture_game` | `… -Phase game` | **0** | 9/9 |
| `regress_mcp044_capture_diff_image` | `… -Phase diff-image` | **0** | 5/5 |
| `regress_mcp045_pixel_compare_cost` | `mcp045_pixel_compare_cost.ps1 -Label post` | **0** | `15/15 checks passed` |
| `regress_mcp046_capture_encode_cost` | `mcp046_capture_encode_cost.ps1 -Label post` | **0** | `23/23 checks passed` |

（mcp044 四相合计 40+8+9+5 = **62/62**，与 `MILESTONES-CLOSURE §4` 记录的 62/62 一致。）

**（c）`-Batch batteries`**（`summary-batteries.txt`，`mcp041` / `mcp042` / `mcp043` 三个门批次）

| 批次 | 退出码 | 步数 | 结果 |
|---|---|---|---|
| `mcp041_gates.ps1` | **0**（399 s；**重跑** 399 s） | 17 | 首轮 16 步 exit 0 + `gate4_full_doctest` exit 1（**同族抖动，§6.5 独立归因 + §6.5.1 A/B + §6.5.2 重跑**）；**重跑 17/17 全 exit 0** |
| `mcp042_gates.ps1` | **0**（429 s） | 19 | **全部 19 步 exit 0** |
| `mcp043_gates.ps1` | **0**（526 s） | 27 | **全部 27 步 exit 0**，含 `gate2g_contract_diff EXIT 0`（§7.3 的定锚修复在批次内生效）、`gate2f_snapshot_after_contract EXIT 0`、`gate1a–1d` 四个组的逐字门 |

**门⑤ `accept_m1.ps1` 连跑两次**（三个批次各一对；逐条比对两次的 PASS 清单）：

| 批次 | run1 | run2 | 两次清单逐字节相同 | FAIL |
|---|---|---|---|---|
| mcp041 | **22/22** | **22/22** | **True** | 0 |
| mcp042 | **22/22** | **22/22** | **True** | 0 |
| mcp043 | **22/22** | **22/22** | **True** | 0 |

### 6.5 `mcp041 gate4` 那一次 exit 1 的独立归因（**不是回归**）

事实（`%TEMP%\mcp041\gates\gate4_full_doctest.log`）：

```
tests\core\io\test_image.cpp(80): FATAL ERROR: test case CRASHED: SIGSEGV - Segmentation violation signal
[doctest] test cases:   467 |   466 passed | 1 failed | 1263 skipped
[doctest] assertions: 83183 | 83183 passed | 0 failed |
```

* 崩的是**引擎自己的** `[Image] Saving and loading`（`tests/core/io/test_image.cpp`：建一张 4×4 图片、存 PNG、再读回），
  **不是**本模块的任何用例；断言失败数为 **0**，是进程段错误把该次运行截断在 467/1727 个用例。
* 同一台机器、同一个二进制上的**另外三次**完整套件运行都全绿且用例数一致：
  本报告门④（`1727 | 1727 passed | 0 failed | 3 skipped`）、`mcp042` 的 `gate4`、`mcp043` 的 `gate4`（见上表），
  三次日志里 `SIGSEGV` / `Unreferenced static string` 计数均为 **0**，只有那次崩溃的运行才有这两类行
  （崩溃后进程在 teardown 阶段破坏了 `StringName` 静态表 —— 是该次崩溃的**后果**，不是它的原因）。
* 这属于本仓库已记录的同族抖动（`--import` 的 `0xC0000005`，`mcp_import_guard.ps1` 正是为它加了有界重试），
  因此本批**不改** `mcp041_gates.ps1` 的断言、也不去「修」引擎：只做**独立复现实验**（§6.5.1）与**重跑**（§6.5.2）。

#### 6.5.1 A/B 复现实验：这次崩溃与本批新增用例无关

同一二进制、严格串行 6 次完整套件：3 次**含**本批用例、3 次 `--test-case-exclude="[MCPServer] TASK-050*"` **排除**本批用例
（逐次日志与摘要：`docs/reports/evidence/task050/green/flake-ab/`）。

```
with    run1 exit=0 crashes=0 :: test cases: 1727 | 1727 passed | 0 failed | 3 skipped
with    run2 exit=0 crashes=0 :: test cases: 1727 | 1727 passed | 0 failed | 3 skipped
with    run3 exit=0 crashes=0 :: test cases: 1727 | 1727 passed | 0 failed | 3 skipped
without run1 exit=0 crashes=0 :: test cases: 1723 | 1723 passed | 0 failed | 7 skipped
without run2 exit=0 crashes=0 :: test cases: 1723 | 1723 passed | 0 failed | 7 skipped
without run3 exit=0 crashes=0 :: test cases: 1723 | 1723 passed | 0 failed | 7 skipped
```

**结论**：6/6 全绿、`SIGSEGV` 计数 0；排除本批用例后用例数正好 −4、skipped 正好 +4（3 → 7），证明过滤确实生效。
加上 §6 门④ 与 `mcp042`/`mcp043` 的两次，本二进制共 **7 次**完整套件全绿 vs **1 次**同族抖动
（约 1/8，抖动用例在引擎侧、断言失败数为 0）。因此这次 exit 1 **与本批改动无关**，
也不存在「本批用例触发了它」的证据（含/不含本批用例的两组都全绿）。

#### 6.5.2 重跑 `mcp041_gates.ps1`：**17/17 步 exit 0**

重跑摘要在 `docs/reports/evidence/task050/green/regression/mcp041_gates_rerun_summary.txt`，
其中 `gate4_full_doctest EXIT 0 (35s)`，日志 `docs/reports/evidence/task050/green/flake-ab/mcp041_rerun_gate4_full_doctest.log`
（sha256 `082b7c804417461b9134edbead96efb8fed04aeb5c3ea42b4d97b660681266e4`）：

```
[doctest] test cases:   1727 |   1727 passed | 0 failed | 3 skipped
[doctest] assertions: 446649 | 446649 passed | 0 failed |
```

因此 `mcp041` 门批次**以重跑的全绿结果为准**（17/17，含 `accept_m1` ×2 各 22/22、六个回归脚本全 0），
首轮的 `gate4` exit 1 按 §6.5/§6.5.1 归因为同族抖动，且**没有**削弱任何断言、没有改 `mcp041_gates.ps1` 一行。



---

## 7. 横切改动的**逐条归因**（谁被影响、为什么、改了什么）

本批只**增补** `-32602` 的 `data`，但横切改动必须把「谁会因此变红」逐条查清。

### 7.1 被本批**修改**的既有断言（1 处，且是加强）

| 位置 | 旧断言 | 新断言 | 归因 |
|---|---|---|---|
| `tests/test_mcp_server.h:5014-5015`（`the editor write tools validate their arguments before touching the editor` 的 `expect_invalid` λ） | `CHECK_FALSE(error.data.get_type() == Variant::DICTIONARY)`，注释「`-32602` never carries `data.suggestion`」 | `CHECK(error.data.get_type() == Variant::DICTIONARY)` + 建议**非空**且**含工具名** | 旧断言把 O-1 的缺陷写成了不变量。这是**加强**（从「必须没有」变成「必须有且可用」），不是放宽；同一 λ 里检查错误码与消息文本的两行**一字未改**。红相位里它确实以 `DICTIONARY == NIL` 失败 |

其余既有断言**一条都没动**。特别是 TASK-032 的全工具「未知参数」扫描
（`an undeclared argument name is refused, never ignored`）**逐字相等**的断言仍然成立——
因为未知参数门有建议时 `_add_invalid_params_suggestion` 直接返回（实测 `e15` 215 B → 215 B）。

### 7.2 被本批**影响但无需修改**的脚本（已实跑，见 §6.4）

现有回归/证据脚本对 `-32602` 的检查形态是「**错误码 + 消息片段**」，**没有一处断言 `data` 缺席**
（普查：`scripts/**` 里 `-32602` / `Missing required` 相关断言 250+ 处，逐一读过；
唯一的 `data` 读取全部是 `$e.data.suggestion` 的存在性/内容检查，只会因为新增建议而更容易通过）。
因此「错误码与消息文本不得改变」是本批唯一真正要守的边界，而它守住了（§3.1、§7.1）。

### 7.3 被本批**影响且必须动**的脚本（1 处，断言未放宽）

| 脚本 | 现象 | 处理 | 归因 |
|---|---|---|---|
| `scripts/mcp043_gates.ps1` 的 `gate2g_contract_diff` | 该步把 `scripts\mcp043_contract_diff.py` 的**右侧**指向**实况**契约，脚本里还硬写了 `generator_version == "1.11.0"`；任何后续任务合法地改契约（本批的 N-2 描述 append 就是）都会让它红 | 只改**调用侧**：右侧改为与左侧同样**按 revision + sha256 钉死**的 `47b5008bac`（`443f1df2…`）；`scripts/mcp043_contract_diff.py` **一字未改**（没有任何断言被放宽） | 这一步的主题是**TASK-043 那次改动**，不是「之后没有任务动过契约」；钉死锚点对之后它仍然逐字证明 TASK-043 的 diff。实测：`changed tools = 那 5 个；overrides 18 -> 23；problems = 0`。本批自己的契约改动由新的 `mcp050_contract_diff.py` 负责 |

### 7.4 明确**不**纳入回归的一条（照实说明）

`scripts\mcp044_zero_change.ps1` 需要**TASK-044 之前的二进制**（`-Mode capture -EnginePath <pre 构建>` +
`-Mode compare -PreDir/-OffDir/-OnDir`）。该二进制无法从本锚点重建，因此**本批不跑它**，
也不拿任何一个替身去凑绿；TASK-044/045/046 的可重跑回归按 `MILESTONES-CLOSURE §4` / `REPORT-048 §7`
的口径执行（`mcp044_capture_evidence.ps1` 四相 + `mcp045 -Label post` + `mcp046 -Label post`，见 §6.4）。

---

## 8. 决策与偏离（供决策者复核）

| # | 决策点 | 选项（含被否决者） | 选择与理由 |
|---|---|---|---|
| D1 | 建议生成放在哪 | ① ~30 个 handler 各写一份；② 传输层；③ **注册表两个入口** | **③**。handler 唯一可达路径就是这两个入口（GDR-19 §17.2），且它们持有 `inputSchema`；171 条一次覆盖、未来工具自动继承；传输层会漏掉进程内路径 |
| D2 | `-32602` 的哪些部分可变 | 只有 `data` 可变 | `code`/`message` 冻结（任务书 §4），只有 `data.suggestion` 增补；已有建议一律不覆写 |
| D3 | N-2 的回答形态 | ① `valid:null` + 说明；② **`-32000` + `data.suggestion`**；③ 回退+加注释 | **②**（§5.2）。理由：`null` 在客户端 falsy；`DESIGN-DETAIL §16-10` 对「构建缺能力」已有同族裁决；拒绝里没有 `valid`，误读不可能发生。**这是对审计建议 `valid:null` 的显式偏离** |
| D4 | 接受参数列表的顺序 | ① 契约文件键序；② 运行时 `inputSchema` 键序；③ 排序 | **②**：与 TASK-032 门逐字断言的同一列表（同一 helper），确定性最强、零漂移风险；①需要运行时读契约文件（进程内不可取）且少数手写块本就不同；③会改变既有 TASK-032 断言 |
| D5 | 认不出参数名时 | ① 留空（任务书禁止）；② 只列接受参数；③ **说明原因 + 列接受参数** | **③**（N-7「不得留空」） |
| D6 | 嵌套裸数组（契约无 `items`） | ① 猜一套词表；② **说明 schema 不足 + 列接受参数** | **②**。生成器是 schema 驱动的，不引入每工具词表（会腐烂）；`events` 的 `items` 缺口是审计 O-4 的主题，不在本批范围 |
| D7 | 扫描的「状态优先」例外 | ① 静默跳过；② 放宽成「不计较」；③ **写死例外名单并断言例外数** | **③**：静默跳过会让扫描悄悄缩水；名单是用空调用**实测**出来的完整例外集（1 个） |
| D8 | TASK-043 门批次的契约 diff | ① 放宽/删除该步；② 留着红并归因；③ **两侧都钉在 TASK-043 的锚点对** | **③**（§7.3）：断言一字未改，主题回到 TASK-043 自己 |
| D9 | 证据存放 | ① 只留 `%TEMP%`；② **复制进仓库** | **②**（审计 N-6 的教训：`%TEMP%` 会丢）。体积是 29×2×2 个小 JSON + 日志，可接受 |
| D10 | 契约描述字面量 | 手工转抄 vs **脚本从契约逐字复制** | **脚本复制**（`%TEMP%\mcp050\patch_literal.py`，含「需要转义就报错退出」的守卫），避免中文转抄错一个字节就撞门① |

---

## 9. 遗留风险与限制（诚实声明）

1. **N-2 的字节级差异只在 `module_mono_enabled=no` 构建上实测**。mono 构建在本锚点**停在旧 revision**
   （【实测】`bin\godot.windows.editor.x86_64.mono.console.exe --version` =
   `4.8.dev.mono.custom_build.019c4b019`，二进制时间戳 `2026-09-24 13:39:15`，**≠** 非 mono 的 `4.8.dev.custom_build.<HEAD>`），
   因此「有 C# 后端时 `.cs` 走真 `CSharpScript::reload()`」这一支**未被本批重测**，
   只是**未被本批改动**（`COMPILE` 分支的代码与旧实现逐字相同）。这与审计 §0.3 记录的限制同源
   （审计在 `5ee2c596a` 上也读到同一个 mono 二进制）。
2. **`valid:null` 路线被判否**（D3）。若决策者认为契约应保留 `valid` 字段，则需回到设计阶段改本批的拒绝形态，
   并同步改 `DESIGN-DETAIL §16-10` 的适用解释——本报告已把取舍与理由摆明，不自行改设计文档。
3. **接受参数列表的顺序口径**是「运行时 `inputSchema` 键序」（D4）。少数手写注册块与契约文件键序不同
   （实测 `project_get_settings`），门① 用规范化 JSON 比较因而看不到；若要「与契约文件逐字同序」，需要
   单独一批去对齐 ~30 个手写注册块，**不属于本批**（任务书禁止改 handler）。
4. **建议内容的语义词表仍来自契约**：契约里参数类型/枚举写得含糊的地方（例如只有 `type: "object"` 而无
   `properties` 的对象、或契约完全没写的嵌套形态），建议只能给出「`an object`」+ 接受参数列表。
   本批不引入每工具的人工词表，因此这类形态的引导强度**有上限**——这是设计选择，不是遗漏。
5. **门⑥a 的信息性行号漂移仍是 11 条**（与 REPORT-048/049 相同），漂移行全在本批**未触碰**的文件里；
   `scanned == pinned == 75`，本批**新增收窄点 0 个**。
6. **`-32602` 未知工具名带建议的分支只在进程内可达**（线上传输层先答 `-32601`）。该分支已由 doctest 断言，
   但**没有**线证据（实测 `e19` 记录的就是传输层行为），避免把它说成「线上可见」。
7. **门①/②/⑥c 的日志与响应进了仓库**，但 `curl` 响应里含本机绝对路径（scratch 工程路径），
   与既往批次的证据格式一致，不含任何密钥。

---

## 10. 结论（按 D86 标锚点）

* 本批的**开工锚点**是 **`889466b85cd462fd24444d6d7ab53efbe0a44d6e`**：红相位测的是它（未提交改动树）的**改动前**二进制
  （`git stash` 三份实现文件后重建）。绿相位与全部门的**源码树**是**实现提交 `b8b6553d9`**，
  版本串随构建时机变化而源码不变（§0.1 已逐一点名四个同源二进制，§11 是提交锚点表）。
* **O-1**：171 条工具有必填参数的 151 次空调用扫描 + 8 类定向探针，缺必填的 `-32602` 从 96–100 B 变成带建议的
  219–367 B；immediate/deferred 两条入口、省略/为空两种情形都覆盖。
* **N-7**：任何 `-32602` 都不留空——嵌套路径能定位（`events[0].type` / `steps[0].type`），
  契约能解析的给类型+枚举+必填性，解析不了的**说明原因**并给接受参数列表。
* **N-2**：合法 `.cs` 从 `valid:false / ERR_PARSE_ERROR` 变成 `-32000` + `data.suggestion`；
  `valid` 语义由契约描述写清（append，生成器 1.12.0）；门① 逐字通过。
* 五道门 + 门⑥ 三段 + 两个契约 diff + 回归批次全绿（§6）；被影响的既有断言只有 1 处且是**加强**（§7.1），
  被影响的脚本只有 1 处且**断言未放宽**（§7.3）。

---

## 11. 提交锚点（D86）

| 提交 | 内容 | 与门的关系 |
|---|---|---|
| `889466b85cd462fd24444d6d7ab53efbe0a44d6e` | **开工 HEAD**（`docs(mcp_server): the racing-backlog audit, TASK-048/049 briefs and reports, TASK-050`） | 红相位测的是它的**改动前**二进制（`git stash` 三份实现文件后重建） |
| `b8b6553d90d1d60b6bf730b6003d4b745e2e749c` | **实现 + 测试 + 生成器 + 契约 + 三个新脚本 + `mcp043_gates.ps1` 定锚修复**（10 files，+1795/−37） | **本报告所有门（①②③④⑤⑥、契约 diff、回归批次）测的就是这个提交的源码树**；提交后普通重建 → `--version = 4.8.dev.custom_build.b8b6553d9` == 短 HEAD |
| **本报告提交** | `a95c0bf1e890475689495a32988bca9386c9df2e`（短 `a95c0bf1e8`）——`docs/reports/REPORT-050-parameter-guidance.md` + `docs/reports/evidence/task050/**`（152 个文件，其中 28 个 `.log` 用 `git add -f`） | 该提交的**源码树与 `b8b6553d9` 相同**（`git diff --name-only b8b6553d9 a95c0bf1e8` 不含任何 `.cpp`/`.h`）。提交后普通重建 → **`--version = 4.8.dev.custom_build.a95c0bf1e` == 短 HEAD `a95c0bf1e`**，并复跑门③（301/301、22367）与门④（1727/1727、446649、0 failed、3 skipped），均 exit 0 |
| **两处报告勘误**（只是 `docs/**`） | `bef296415dbdedcb18979844d8a987f2addd401f`（§0.3 的证据文件计数修正 + §0.1 的复验结果）与 `8797c16a129f6139123569799b870a0d6d86f03c`（§0.1 把「四个同源二进制」逐一点名） | 两次的源码树仍与 `b8b6553d9` 相同；每次之后都普通重建并复验 `--version == 该提交`（实测：`bef296415` 与 `8797c16a1` 均匹配），门③/④ 复跑同为 301/22367 与 1727/1727、446649、0 failed |
| **`docs/**`-only 提交的一般规则**（本节所在的提交也适用） | 任何只改本报告/证据的后续提交 | 源码树恒等于 `b8b6553d9`（`git diff --name-only b8b6553d9 HEAD -- "*.cpp" "*.h"` 为空即证）；重建后 `--version` 必然等于该提交的短哈希，门③/④ 必然复现同一组数字 —— 这一条不需要逐提交再写一行 |

> `--version` 的复验方式（可复算）：`git rev-parse --short=9 HEAD` → `modules\mcp_server\scripts\build_local.cmd` →
> `bin\godot.windows.editor.x86_64.console.exe --version`；本任务最后一次实测为
> `version=4.8.dev.custom_build.8797c16a1 head=8797c16a1 match=True`，同一次二进制上门③ `301 | 301 passed | 0 failed | 1429 skipped`
> / `22367`、门④ `1727 | 1727 passed | 0 failed | 3 skipped` / `446649`，均 exit 0。

**提交信息与决策的对应**：实现提交的信息逐条列出 D1–D10 的落地（两个入口、只增补 `data`、
`-32000` 而非 `valid:null`、schema 驱动的建议、裸数组说明原因、扫描例外名单、契约 append 与生成器 1.12.0），
使「改动 → 提交 → 报告决策表」三者可互查。

**未做的事（照实说）**：未 `push`；未改 `hof-rs`（只读，决策日志 `F:\moonbit-hof-rs\DECISIONS.md` 不在本 fork，
本任务不写它，本报告即本批的完整决策记录）；未新建任何竞争性规范/日志文档；未改 `docs/DESIGN-DETAIL.md`。
