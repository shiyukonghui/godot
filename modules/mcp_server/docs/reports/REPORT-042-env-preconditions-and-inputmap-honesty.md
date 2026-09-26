# REPORT-042 — 6 个回归脚本的 9877 前置对齐 + `project.godot` 重写实测 + O-6 诚实化

> 任务书：`docs/tasks/TASK-042-env-preconditions-and-inputmap-honesty.md`；手册：`docs/tasks/PLAYBOOK-group-port.md`。
> 本报告只报告**模块**的改动与证据；**未改** `docs/DESIGN-DETAIL.md`、**未改**契约/映射/组清单/生成器
> （§1.3 的 sha256 与 REPORT-041 逐字相同），**未新建**任何竞争性规范文档（PLAYBOOK §7.2）。
> 9877 自始至终**只被观察**（`Z01` 的证据行给出 `classification`），本批**没有**终止/重启任何进程。

---

## 0. 结论速览与锚点（D86）

| 项 | 值 |
|---|---|
| 仓库 / 分支 | `F:\RustProjects\godot-mcp-pro\code\godot` / `feature/mcp-server-module`（**未 push**） |
| **① 脚本锚点（6 脚本对齐 + 门⑤ 补强 + 探针）** | `b72c09a3ea` — `mcp_server: TASK-042 section 1 - one shared 9877 classification for the six regression scripts, and a vanished-listener case for gate 5` |
| **③ O-6 代码锚点** | `d5b98df19a` — `mcp_server: TASK-042 section 3 - editor_add_input_action answers action_state and project_entry, so a pre-existing (built-in) action cannot read as 'nothing happened'` |
| **②③ 证据脚本与门驱动锚点** | `3b7a3c19b1` — `mcp_server: TASK-042 sections 2-3 evidence - project.godot rewrite measured on a real commented project, plus the splice spike and the serial gate battery` |
| **门的被测提交（本报告全部门与线上证据测自它）** | `3b7a3c19b1`（= 上面第三个提交） |
| **门的被测二进制** | `4.8.dev.custom_build.3b7a3c19b` == `git rev-parse --short=9 HEAD`（`scripts\build_local.cmd -Force`，`tests=yes`，**从 cmd 启动**，串行） |
| ① 的结果 | 6 个脚本的 9877 断言从「**必须有监听者**」改为共享的六分类（+1 条更严的第七类），实测 **0 失败**（§2.5） |
| ② 的结果 | **引擎侧不可避免**（`save_custom` 只有整文件写入）；**存在可行方案**（纯文本拼接 `[input]` 条目，已用真实游戏进程证实可被引擎读回），是否实施交决策者（§3） |
| ③ 的结果 | 响应新增 `action_state` / `project_entry` 两个字段（**未新增参数**、`inputSchema` 零改动）；内置名 `ui_accept` 实测 `created=false` + `action_state=pre_existing_unchanged` + `project_entry=created` + `persisted=true`（§4） |
| ④ 的结果 | 只写**待立项说明**，未实现（§5） |
| **本报告提交** | `10dfe36a69`（→ `10dfe36a6`）本报告 + `evidence/task042/**`；证据目录的**字节保真**在 `a502516976` + `8fb95f4208`（只加 `evidence/task042/.gitattributes` 与重规范化 4 个 CRLF 文件） |
| **D86 论证** | `git diff --stat 3b7a3c19b1 HEAD -- modules/mcp_server/tools modules/mcp_server/tests` **为空** ⇒ **门的被测代码 == 门批次提交 `3b7a3c19b1`**（与 REPORT-040/041 同一种论证） |
| 门结果一句话 | ①/②/③/④/⑤/⑥ 见 §6；回归脚本群见 §7 |
| 契约/组清单/DESIGN-DETAIL | **未改**（sha256 见 §1.3） |

---

## 1. 交付面

### 1.1 提交

| sha | 说明 |
|---|---|
| `b72c09a3ea` | ①：新增共享助手 `mcp_port_guard.ps1` + 探针 `mcp042_port_guard_probes.ps1`；6 个回归脚本对齐；`accept_m1.ps1` 补一类更严的判定（9 增 1 删，纯 ASCII） |
| `d5b98df19a` | ③：`tools/tool_helpers.{h,cpp}` 的 `InputActionPublish` 与回读分类、`tools/editor_input_simulation.cpp` 的两个新响应字段、`tests/test_mcp_server.h` 的新断言 |
| `3b7a3c19b1` | ②③：`mcp042_projectrewrite_and_honesty_evidence.ps1`（30 条检查）与 `mcp042_gates.ps1`（串行门驱动）**← 门批次测的就是这个提交** |
| `10dfe36a69` | 本报告 + `docs/reports/evidence/task042/**`（**没有一个文件进入二进制**） |
| `a502516976` | `evidence/task042/.gitattributes`：该子树 `* -text`，证据字节不做任何换行翻译（仓库根 `.gitattributes` 的 `* text=auto eol=lf` 会改写 CRLF 文件，使 `INDEX.md` 的 sha256 描述的字节不在提交里） |
| `8fb95f4208` | `git add --renormalize` 后的 4 个 CRLF 证据文件：提交后的 blob 字节 == `INDEX.md` 里的 sha256（已用 `git cat-file blob` + sha256 逐字核对，见 §9） |

### 1.2 改动文件与 sha256

| 文件 | 字节 | sha256 | 改动 |
|---|---|---|---|
| `scripts/mcp_port_guard.ps1`（新） | 8 085 | `55b39b08be844a76f27f61faa287c275a0d942694fe3258b33fc84374f347fe9` | 9877 的**唯一**判定：解析我方命令行端口 → 记录我方 pid/命令行 → 七分类判定（纯 ASCII） |
| `scripts/mcp042_port_guard_probes.ps1`（新） | 9 143 | `f5d2105a62c88ada31a02377614e8aee1a9543fcfd16e727bfcfd11542070279` | 21 条探针：每种分类可达、三种违规**必须 FAIL**、6 个脚本不再带旧断言（纯 ASCII） |
| `scripts/mcp042_projectrewrite_and_honesty_evidence.ps1`（新） | 27 413 | `c4718bb4c75836e41fb46644f71cd6bec6a94b044c8e2b70c8a6bd925a6c6dfa` | ②③ 的线上证据（30 条检查，纯 ASCII） |
| `scripts/mcp042_gates.ps1`（新） | 5 022 | `5ab9119e083e3b1a87b40ca99735fae20f789d4d75a5cdb14ae9c353fe11bf24` | 本轮门批次的串行驱动（每步独立日志 + 退出码） |
| `scripts/accept_m1.ps1` | 67 038 | `2ebbe68f0b5955e79f13b57889e64ef5abd5865a0d4ef1315305686c5fb7b10a` | 门⑤ 的 9877 判定新增 `user_editor_vanished_during_the_run`（见 §2.2） |
| `scripts/mcp032_d3_d4_d6_evidence.ps1` | 31 105 | `b93065eca165a9eccd5b814173c87450af6d0777d9b54bc37a3ec83fcbe6e323` | `Start-Engine` 登记 pid+命令行；前后两条断言 → 一条 `port_9877_guard` |
| `scripts/mcp033_b5_animation_evidence.ps1` | 36 135 | `8027f65b8cb98d3f3a8f2ce1630260ad2c2b59ea39803d520de5d21a97fedbec` | 同上 |
| `scripts/mcp034_b5_audio_particle_theme_evidence.ps1` | 64 429 | `d18ebc0d9b6afa69b27f4a8158bbea62543c7b3a8c524b8745448a2d53965906` | 同上 |
| `scripts/mcp035_b5_tilemap_shader_physics_evidence.ps1` | 50 552 | `d716b27cc039fed188eea11d72d54459bed6c5b7aaccbeb1dfc7fc3e58861f71` | 同上 |
| `scripts/mcp036_b5_navigation_theme_export_android_evidence.ps1` | 60 833 | `fec9f071d7f93cd0d9133a38d29b3caee0890e1cd9c04fda637ee242221ca6fd` | 同上（含两条 `--import` 命令行登记） |
| `scripts/probe037_d2_d1_r1r2.ps1` | 30 349 | `fdb522590dd8d21bda67b12a3269ef7e55c79d61c8995c289d565409c9a53e11` | 同上 |
| `tools/tool_helpers.h` | 72 981 | `69ccd67ffd7ff541ffed3c46657fd9af7b2ec1a2ef9bb9001404cf4d188db088` | `enum class InputActionPublish` + `input_action_publish_name` + 两个 `out` 参数 |
| `tools/tool_helpers.cpp` | 128 387 | `26dc84232db43ed4eb19efad520cb3ddf1df1445ec7ed7c06554b4427cccb26f` | `_input_action_entry_state_on_disk`（用引擎自己的 `ConfigFile` 读**磁盘**上的旧状态）+ 分类产出 |
| `tools/editor_input_simulation.cpp` | 57 806 | `140d9ec3fbeeb6b88ffc295fee59b6281c52039f544b0635416f5893f5037537` | 写入前记录 `events_before`；响应新增 `action_state` / `project_entry`；契约注释同步 |
| `tests/test_mcp_server.h` | 960 094 | `bd5deb301ff9c1ae98d1fa50445f9a0183832e012a82f26bceff87b9d25e8b00` | 工具级 4 条新断言 + 帮助器级 `Created/Unchanged/Replaced/Unknown/None` 与线缆拼写 |

> `.ps1` 全部纯 ASCII：4 个新脚本与 6 个回归脚本的非 ASCII 字节 = 0；`accept_m1.ps1` 的 22 个非 ASCII
> 字节是**既有**的 `§`，`git diff` 的**新增行里零非 ASCII**（已用 `findstr` 核对，见 §6.0）。

### 1.3 未改动的规范面

| 文件 | 字节 | sha256 |
|---|---|---|
| `docs/tools_list.renamed.json` | 110 770 | `c844ec8af9ef00d2e6ec7008c9806b3e2b16757e78794d3ccca0704edf844256`（**与 REPORT-041 逐字相同**） |
| `docs/DESIGN-DETAIL.md` | 71 551 | `7e84bf874934aaff9129b2558832247adf8153bb7deb26495ffb3291fc4e1784`（**未改**） |

---

## 2. ① 6 个回归脚本的 9877 前置对齐

### 2.1 旧断言为什么不是回归

6 个脚本各有一对断言，形如：

```
Check 'port_9877_owner_before'    ($userPidBefore -gt 0) ...      # 9877 上必须有监听者
Check 'port_9877_owner_after'     ($userPidAfter -eq $userPidBefore)
```

第二半（「前后一致」）在本环境里**一直是 PASS**（`-1 == -1`）；失败的是第一半——它要求**用户的 Godot 正在运行**。
TASK-040/041 已两次把这类失败逐条归因成「环境事实，不是回归」（REPORT-041 §7），门⑤ 也在 TASK-041 被改成
可区分的六分类。但 6 个脚本仍带着旧形态，于是「用户没开 Godot」时它们**永远 exit 1**，持续污染后续批次的
「全绿」判读（REPORT-041 §9.3 风险 5）。本批消除它。

### 2.2 判定：六分类，外加一条**更严**的第七类

共享助手 `scripts/mcp_port_guard.ps1` 把判定收成一处，分类**与门⑤ 逐字一致**（含证据行字段）：

| # | classification | pass | 依据 |
|---|---|---|---|
| 1 | `violation_this_script_requested_the_user_port` | **FAIL** | 我方任一自启进程的命令行里出现过 `--mcp-port=9877`（从**真实参数**读，不靠调用点假设） |
| 2 | `violation_this_script_owns_the_user_port` | **FAIL** | 9877 的监听者 pid ∈ 我方自启 pid 集合 |
| 3 | `environment_fact_no_listener_before_or_after` | PASS | 前后都没有监听者（**明写分类**，不能被读成「我们证明了没占用」） |
| 4 | `user_editor_vanished_during_the_run` | **FAIL** | **本来有**监听者、现在没有 |
| 5 | `foreign_listener_appeared_during_the_run` | PASS | 本来没有、现在有，但**不是我们**的 pid |
| 6 | `user_editor_present_untouched` | PASS | 本来有、现在还是**同一个 pid** |
| 7 | `user_editor_pid_changed_during_the_run` | **FAIL** | 本来有、现在是**别的 pid** |

> **第 4 类是本批新增的、比门⑤ 的六分类更严的一类，必须说明白**：TASK-041 的门⑤ 把
> 「`-not $userPortAlive`」放在「`pid_before -le 0`」之前，于是「**用户编辑器本来在、这次运行后不见了**」
> 会落进 `environment_fact_no_listener_before_or_after` 并 **PASS** —— 而旧的 `-gt 0` + `-eq` 断言在这一
> 情形下是 **FAIL**。也就是说，直接照抄六分类会在这一格上**放松**真不变式。
> 本批把这一类单独拆出来判 FAIL，并**同时**把同一修法落进 `scripts/accept_m1.ps1`
> （新增 9 行、删 1 行，纯 ASCII），让门⑤ 与 6 个脚本共用同一套语义。当前环境 `pid_before=-1`，
> 所以门⑤ 的行为**没有变化**（仍是 `environment_fact_...` / 22/22 ×2，见 §6.5）。

强度对比：旧断言要求「9877 上必须有监听者且 pid 不变」；新判定**多**了两条更强的机器事实（我方 pid 集合、
我方命令行端口），在「有监听者」的所有情形下**仍然**要求 pid 不变，并把旧断言会 FAIL 的「本来在、后来不见了」
继续判 FAIL。唯一被放宽的是「一个本来就没有监听者、之后也没有」的环境——那正是任务书 §0.1 要求区分的那一类。

### 2.3 共享助手与探针（21/21 PASS）

除分类外，助手还做两件旧脚本没做的事：

1. `Get-McpPortsInCommandLine` 解析命令行里的 `--mcp-port=<n>` 与 `--mcp-port <n>`，并把端口当**整数**比：
   `--mcp-port=98770` 是 **98770**，前缀匹配是这类守卫最经典的假绿；
2. 每个自启进程用它**真实的参数**登记（`Start-Engine` 里 `Register-McpPortGuardProcess -EnginePid $handle.Id -Arguments $Arguments`），
   `Import-McpProject` 的 `--import` 启动也把 `$import.command` 登记进去（它们用 `--mcp-port=0` 或 9888，
   从不请求 9877）。

`scripts/mcp042_port_guard_probes.ps1`（21 条，**exit 0**）证明这套判定**不是恒真**：7 种分类各有一条可达
探针，三种违规分类（含新的第 4 类）**必须返回 pass=false**，此外还有「别的端口不被误报成用户端口」、
「`--import` 的命令行也被覆盖」、「6 个脚本里旧断言已不存在且都引入了共享助手」、
「门⑤ 也知道新的第 4 类」。逐字证据见 §6.6。

### 2.4 对齐前后逐条对照

| 脚本 | 对齐前检查数 / 结果（REPORT-041 §7） | 旧断言 id | 对齐后检查数 | 新断言 id |
|---|---|---|---|---|
| `mcp032_d3_d4_d6_evidence.ps1` | 39 / 38 PASS 1 FAIL | `port_9877_owner_before` + `port_9877_owner_after` | **38** | `port_9877_guard` |
| `mcp033_b5_animation_evidence.ps1` | 75 / 74 PASS 1 FAIL | 同上 | **74** | `port_9877_guard` |
| `mcp034_b5_audio_particle_theme_evidence.ps1` | 114 / 113 PASS 1 FAIL | `port_9877_owner_before` + `port_9877_owner_unchanged` | **113** | `port_9877_guard` |
| `mcp035_b5_tilemap_shader_physics_evidence.ps1` | 67 / 66 PASS 1 FAIL | `port_9877_owner_before` + `port_9877_owner_after` | **66** | `port_9877_guard` |
| `mcp036_b5_navigation_theme_export_android_evidence.ps1` | 59 / 58 PASS 1 FAIL | `port_9877_guard_before` + `port_9877_guard_after` | **58** | `port_9877_guard` |
| `probe037_d2_d1_r1r2.ps1` | 40 / 39 PASS 1 FAIL | `port_9877_owner_before` + `port_9877_owner_unchanged` | **39** | `port_9877_guard` |

每条脚本的检查数净 **−1**（删 2 条旧断言、加 1 条更强的合并断言）；**没有任何检查被删除而不被替代**。
`probe037` 的收口断言在 `finally` 里、`mcp036` 的收口断言在其自有 `guardAfter` 处，两者都是原地替换。

### 2.5 复跑与逐条归因

命令：`powershell -NoProfile -ExecutionPolicy Bypass -File scripts\<脚本>`，串行（由 `mcp042_gates.ps1` 驱动，
两个引擎从不同时启动），与门批次同一二进制（`3b7a3c19b`）。

| 脚本 | 对齐后检查数 | 结果 | `port_9877_guard` 的证据行（逐字） |
|---|---|---|---|
| `mcp032_d3_d4_d6_evidence.ps1` | 38 | **38 PASS / 0 FAIL**（exit 0） | `listening=False pid_before=-1 pid_after=-1 ours=False same_pid=True asked_by_us=False classification=environment_fact_no_listener_before_or_after our_pids=[29352,75636] our_ports=[0,9888,9889] our_command_lines=3` |
| `mcp033_b5_animation_evidence.ps1` | 74 | **74 / 0**（exit 0） | 同上形态：`our_pids=[77448,46216] our_ports=[0,9888,9889] our_command_lines=3` |
| `mcp034_b5_audio_particle_theme_evidence.ps1` | 113 | **113 / 0**（exit 0） | `our_pids=[74924,69668] our_ports=[0,9888,9889] our_command_lines=3` |
| `mcp035_b5_tilemap_shader_physics_evidence.ps1` | 66 | **66 / 0**（exit 0） | `our_pids=[73280,62916] our_ports=[0,9888,9889] our_command_lines=3` |
| `mcp036_b5_navigation_theme_export_android_evidence.ps1` | 58 | **58 / 0**（exit 0） | `our_pids=[77760,72596,77056] our_ports=[9888,9889] our_command_lines=5`（两条 `--import` 也登记了） |
| `probe037_d2_d1_r1r2.ps1` | 39 | **39 / 0**（exit 0） | `our_pids=[76600] our_ports=[0,9888] our_command_lines=2` |

**逐条归因**：

1. **TASK-040/041 里 6 个脚本的唯一失败项（「9877 上必须有监听者」）已消失**，且不是被「恒真」掩盖的：
   证据行里 `asked_by_us=False`、`ours=False`、`same_pid=True`、`classification=` 明写，且 `our_ports` 证据
   显示我方请求过的端口是 `0/9888/9889`（`--import` 用 `--mcp-port=0`），**没有一个脚本请求过 9877**。
2. **没有新的失败**：6 个脚本除了这一处断言外全部保持原样，检查数净 −1（删 2 合并为 1），
   其余用例与 TASK-041 的复跑结果一一对应（当时它们也是 PASS）。
3. **`mcp040` 两个脚本 0 失败**（`mcp040_defect_probes -Label task042` 47/0；`mcp040_racing_regression` 35/0），
   它们本来就只断言「9877 owner 前后一致」，没有「必须有监听者」这一半——本次对齐**没有**动它们。
4. **9877 全程未被占用**：本批唯一出现过的 9877 监听者是**没有**（`pid_before=pid_after=-1`）；
   本批**没有**终止、重启或以任何方式接触任何进程。

---

## 3. ② `project.godot` 重写影响实测

### 3.1 样本与实验设计

样本是**本 fork 自带的一份真实、带注释的工程文件**：`modules/gdscript/tests/scripts/project.godot`
（407 字节，sha256 `d26d9950…c98ca`）。它恰好具备要测的全部特征：

* 4 行**手写注释**，其中一行写着「please don't let the editor changes be saved」；
* 一个**已存在**的 `[input]` 动作（`test_input_action`），**手写格式**为多行；
* 引擎设置（`settings/gdscript/always_track_call_stacks`）与 `config/name`。

实验把它**逐字节复制**到 `%TEMP%\mcp042-rewrite\proj`（`Copy-Item`，前导 sha256 相等即 `A01`），
在原文件**从不被触碰**的前提下跑：起编辑器（9888）→ `editor_add_input_action{action:"mcp042_mirrored_action", key:"J"}`
→ 逐字节比较。为了不往 `project.godot` 里塞 harness 专用行，游戏场景是从**命令行**给的
（`main.cpp:2033-2036`：未识别参数进 `main_args`，于是 `:2317` 的「没有主场景」中止被跳过；`:4088-4104` 载入该场景）。

### 3.2 逐字节差异：丢了什么、保留什么

```
sha256  d26d9950…c98ca (407 B)  ->  1b12f920…464b9 (869 B)
```

| 事实 | 证据（`A*_` 检查 id） |
|---|---|
| 整个文件被重写（不是局部） | `A21`：sha256 与字节数都变了；文件头变成引擎固定的 7 行 `; Engine configuration file.` 块（`A23`） |
| **4 行手写注释 4/4 全部丢失** | `A22`：`comments lost 4/4; kept 0` |
| 除注释外**没有别的行丢失** | `A26b`：原文件非空行中「不再逐字存在」的恰好是那 4 行注释 |
| 已有动作的**手写多行格式原样保留** | `A26`：`test_input_action={…}` 块（51 字符、多行）逐字节仍在 |
| 引擎设置与 `config/name` 保留 | `A24` |
| 新动作落进 `[input]` | `A25`：一条 `{"deadzone","events":[Object(InputEventKey,…)]}`，21 行、386 字符 |
| 第二次同参调用**字节不变** | `A27`：sha256 不变；`action_state=pre_existing_unchanged`、`project_entry=unchanged` |
| 编辑器退出**不再改文件** | `A28`：退出前后 sha256 相同 |
| 引擎**新增**了一行 `config/features=PackedStringArray("4.8")` | 差异文件（`save_custom()` 会补齐 features，`project_settings.cpp:1238-1264`） |

差异文件（报告附件 `project-godot-rewrite-diff.txt`）逐行给出 `KEPT`/`LOST`：

```
LOST    1: ; This is not an actual project.
LOST    2: ; This config only exists to properly set up the test environment.
LOST    3: ; It also helps for opening Godot to edit the scripts, but please don't
LOST    4: ; let the editor changes be saved.
KEPT    6: config_version=5
KEPT    8: [application]     KEPT   10: config/name="GDScript Integration Test Suite"
KEPT   12: [debug]           KEPT   14: settings/gdscript/always_track_call_stacks=true
KEPT   16: [input]           KEPT   18..21: test_input_action={ … "events": [] }
```

**没有被这份样本测到、但由源码决定的一点（标注为「推断」，不是实测）**：节/键顺序由
`ProjectSettings::save_custom()` 的 `RBMap<String, List<String>> save_props`（`project_settings.cpp:1306-1321`）
决定，`RBMap` 是按 key 排序的红黑树 → **该文件若手工把节排成非字典序，重写后会被排回字典序**。
本样本的 `[application] / [debug] / [input]` 本来就是字典序，所以**观测不到重排**；这一点我**没有**实测。

### 3.3 为什么引擎侧不可避免（源码锚点）

| 事实 | 锚点 |
|---|---|
| 模块唯一的发布路径就是引擎自己的 `save_custom()` | `tools/tool_helpers.cpp` 的 `publish_project_settings_to`（临时兄弟文件 + rename） |
| `save_custom()` **只**有整文件输出 | `core/config/project_settings.cpp:1234-1341`，末尾必走 `_save_settings_text()` |
| `_save_settings_text()` 先写固定注释头，再遍历**全部**存下来的设置 | `project_settings.cpp:1162-1210`（`:1168-1175` 是那 7 行头；`:1204` 是 `VariantWriter::write_to_string(value, vstr, true)`） |
| `save_custom` 的 `p_custom` 参数只能改「写哪些值」，**不能**改「写哪一段」 | `project_settings.cpp:1294-1304`（仍进同一份 `save_props`） |
| `ConfigFile::save()` 同样是整文件 | `core/io/config_file.cpp:191-211` |
| 注释不属于任何数据结构，`ProjectSettings` 根本没有保存它们的地方 | 全文件搜索无注释保留逻辑；`_save_settings_text` 只写自己的头 |

**结论 A（不可避免）**：**在「用引擎写出口」这条路上，只改 `[input]` 段的局部发布是不存在的**——
没有任何引擎 API 能做到「保留其余字节、只替换一个节」。所以只要 `editor_add_input_action` 走
`publish_project_settings_to`，**加一个输入动作就会重写整个 `project.godot` 并丢掉全部手写注释**。
这一条必须被记载（§3.5 的建议）。

### 3.4 可行方案：只拼接 `[input]` 条目（spike 已验证）

既然引擎不给局部 API，唯一可行的方向是**模块自己按文本拼接**。本批**没有实现**它，但**实测了它可行**：

1. 从引擎刚写完的文件里取出它**自己序列化**的那一条（`B01`：21 行、386 字符，来自
   `VariantWriter::write_to_string(value, vstr, true)`——与 `project_settings.cpp:1204` 同一函数；
   键名会经过 `String::property_name_encode()`，与 `:1205` 同一规则）；
2. 把它**追加**到原始（未重写）的 `project.godot` 末尾（本样本 `[input]` 是最后一节，`B01b` 证明其后没有别的节头）；
3. `B02`：**原始 407 字节是拼接结果的精确前缀**，差异**只有**新增的那一条（387 字符）；
4. 起一个**真实游戏进程**（9889，`--path` + 命令行给场景），它启动时走
   `InputMap::load_from_project_settings()`（`main/main.cpp:2335`）从磁盘重建映射：
   * `B11`：`InputMap.has_action("mcp042_mirrored_action") = true`
   * `B12`：`action_get_events(...).size() = 1`
   * `B13`：既有的 `test_input_action` **也**还在
   * `B14`：游戏运行前后文件 sha256 相同（**读**文件，不发布它）
   * `B15`：4 行注释**仍在**、手写多行块**仍在**、文件仍**恰好等于**拼接文本

也就是说：**「只改 `[input]` 段的局部发布」在引擎之外是可行的**，代价是模块要自己承担文件文本语义。

### 3.5 结论与建议（给决策者）

**两者同时成立，我按诚实原则都报**：

1. **不可避免（就引擎写出口而言，已实测）**：请把「`editor_add_input_action` 会重写整份 `project.godot`、
   手写注释会丢失」写进规范与该工具的 `description`（后者属于契约逐字门的对象 → 需要你裁决一次契约变更）。
   本批**没有**改 `description`（§8 deviations）。
2. **可行方案（已 spike 验证，未实现）**：若「保留注释」是硬需求，就需要一个**显式立项**的
   「`[input]` 条目级拼接发布」helper（本报告 §3.4 就是它的行为规格），并且必须同时规定：
   * 它只动 `[input]` 段的那一条键（新增/替换），其余字节不变；
   * 撞上**无法安全处理**的文件（重复键、`[input.<feature>]` 这类 feature override 段、BOM/CRLF、
     节头缺失）时**拒绝并回落到整文件发布**或直接报错，**不猜**；
   * 它与 `project_set_setting` 的行为**不再一致**（后者仍是整文件），必须写清「谁在什么情况下动多大范围」；
   * 需要一组新的 doctest（含「注释保留」「只动一条键」「异常文件拒绝」）与线上证据。
   **不建议**与本批合并：它改变的是写路径的风险面，且本批的任务范围是「实测 + 结论」。

---

## 4. ③ O-6 诚实化

### 4.1 缺口（TASK-041 §8 已实测，本批修其可读性）

内置动作名（`ui_accept` 等）由 `InputMap::load_default()` 在编辑器进程里存在（`main/main.cpp:2333`），
所以 `editor_add_input_action{action:"ui_accept"}` 的 `created` 恒为 `false`；**但工具照样把编辑器那份
默认绑定镜像进工程 `[input]`**。于是响应里 `created:false` 可以被读成「这次调用什么也没做」——
而磁盘其实变了。缺口不是「写不写」，而是**响应无法区分「新建」与「已存在并被我改动」**。

### 4.2 设计（两个新字段，零新参数）

`created` 的语义**不变**，新增两个正交字段：

| 字段 | 取值 | 含义 |
|---|---|---|
| `action_state` | `created` / `pre_existing_modified` / `pre_existing_unchanged` | 关于**本进程 `InputMap`**：新建了？已存在且这次**真的**加了事件（写入前后 `action_get_events().size()` 比较，不是按请求猜）？已存在且未动？ |
| `project_entry` | `created` / `replaced` / `unchanged` / `none` / `unknown` | 关于**磁盘上的 `[input]` 条目**：这次发布**新建/替换/未变/没写/写了但回读无法确认**（发布前用引擎自己的 `ConfigFile` 读磁盘旧状态，发布后用既有的 `read_input_action_from_disk` 判定） |

* **`persisted` 仍完全来自磁盘回读**（TASK-041 的语义原封不动）：磁盘上没有该动作就 `false` + `persisted_reason`；
  幂等的第二次调用字节不变但条目确实在磁盘上，因此仍是 `true`，而**「这次没改字节」由 `project_entry: unchanged` 表示**——
  这两件事被**分开**表达，而不是让 `persisted` 兼任。
* **不新增参数**：`inputSchema` 零改动，契约逐字门对象（`name`/`description`/`inputSchema`）零改动（§1.3）。
* 若发布成功但回读失败 → `persisted:false` + `project_entry: unknown`（我们写了，但无法确认磁盘现在是什么）。

### 4.3 TDD 红 → 绿（真实输出）

**红 A（行为红，可编译）**：先只加会对新键的断言，重建后
`--headless --test --test-case="*editor input simulation*"`：

```
.\modules/mcp_server/tests/test_mcp_server.h(7594): ERROR: CHECK( created.has("action_state") ) is NOT correct!
.\modules/mcp_server/tests/test_mcp_server.h(7598): ERROR: CHECK( created.has("project_entry") ) is NOT correct!
.\modules/mcp_server/tests/test_mcp_server.h(7628): ERROR: CHECK( again.has("action_state") ) is NOT correct!
.\modules/mcp_server/tests/test_mcp_server.h(7649): ERROR: CHECK( extended.has("action_state") ) is NOT correct!
[doctest] test cases:   2 |   1 passed | 1 failed | 1704 skipped
[doctest] assertions: 223 | 219 passed | 4 failed |
[doctest] Status: FAILURE!
```

**红 B（新 API 不存在）**：把 `MCPTools::InputActionPublish` 与帮助器级用例先写进去 → 测试单元**编译失败**
（`MCPTools::InputActionPublish` 未声明，`scons` 退出码 2）。这是「新能力尚未存在」的红，不是行为红。

**绿**：

```
--test-case="*editor input simulation*"  → test cases: 2 | 2 passed；assertions: 227 | 227 passed
--test-case="*TASK-041*"                 → test cases: 1 | 1 passed；assertions:  59 |  59 passed
[doctest] Status: SUCCESS!
```

**绿阶段里我修过一处自己的错**（如实记录）：第一版 `Unknown` 用例用的内容是
`"this is not a config file {[(\n"`，实测得到 `Created` 而非 `Unknown`。原因在引擎里：
`VariantParser::parse_tag_assign_eof`（`core/variant/variant_parser.cpp:1773-1834`）会把**没有 `=` 的一行**
一路吞到 EOF，`_parse()` 把 `ERR_FILE_EOF` 当 **OK**（`core/io/config_file.cpp:290-291`）——
**`ConfigFile` 对「一行没有 `=`」是宽容的**。改用真正会报 `ERR_PARSE_ERROR` 的未闭合节头 `"[input\n"`
（`variant_parser.cpp:1724-1727`）后转绿。这条引擎事实也写进了测试注释。

### 4.4 线上证据（含内置名）

`scripts/mcp042_projectrewrite_and_honesty_evidence.ps1`：**30/30 PASS**（exit 0）。三条原始响应：

```
A20  新建动作 mcp042_mirrored_action / key=J
     {"action":"mcp042_mirrored_action","action_state":"created","created":true,"event_count":1,
      "key":"J","persisted":true,"persisted_reason":"","project_entry":"created","target":"editor"}

A27  同参第二次（此前动作已存在、绑定未变、条目已在磁盘）
     {"action":"…","action_state":"pre_existing_unchanged","created":false,"event_count":1,
      "key":"J","persisted":true,"persisted_reason":"","project_entry":"unchanged","target":"editor"}

A29  内置动作名 ui_accept（编辑器进程本来就有，3 个默认事件）
     {"action":"ui_accept","action_state":"pre_existing_unchanged","created":false,"event_count":3,
      "key":"","persisted":true,"persisted_reason":"","project_entry":"created","target":"editor"}
```

`A29` 正是 O-6 要求的那一格：**`created=false` 不再等于「什么也没发生」**——`action_state` 说
（本进程映射里它早就有、这次没改它），`project_entry: "created"` 说（但工程 `[input]` 里**这一条是新写的**），
`persisted: true` 说（并且磁盘回读确认了）。`A29b` 进一步确认文件里真的出现了 `ui_accept=` 且带 3 个事件。

**前后对照（同一动作、同一参数）**：

| 场景 | TASK-041 及之前的响应 | TASK-042 之后的响应 | 读法 |
|---|---|---|---|
| 新建动作 + 绑键 | `{"created":true,"event_count":1,"persisted":true,…}` | `+ "action_state":"created","project_entry":"created"` | 动作是新建的，工程条目也是新建的 |
| 已存在 + 同参第二次 | `{"created":false,"event_count":1,"persisted":true,…}` | `+ "action_state":"pre_existing_unchanged","project_entry":"unchanged"` | 动作早就有、这次没改；磁盘字节也没变 |
| 已存在 + 换一个键 | `{"created":false,"event_count":2,…}` | `+ "action_state":"pre_existing_modified"` | 动作早就有，但**这次真的改了它** |
| **内置名 `ui_accept`** | `{"created":false,"event_count":3,"persisted":true,…}` ← **可被读成「什么也没做」** | `+ "action_state":"pre_existing_unchanged","project_entry":"created"` | 动作早就有、没改它；但**工程里这一条是我新写的**（O-6 的镜像） |
| 进程没有 `project.godot` | `persisted:false` + `persisted_reason` | `+ "project_entry":"none"` | 什么也没写：文件名与原因都给 |
| 名字含 `/` 或 `.` | `persisted:false` + `persisted_reason` | `+ "project_entry":"none"` | 同上 |
| 发布成功但回读不确认 | `persisted:false` + `persisted_reason` | `+ "project_entry":"unknown"` | 写了，但**不声称**知道磁盘现在是什么 |

> 负例仍在：`editor_add_input_action{action:"mcp041.dotted"}` 依旧是 `persisted:false` + 原因；
> doctest 里「进程没有 `project.godot`」也依旧是 `persisted:false` + 原因 + `project_entry: "none"`。

---

## 5. ④ O-4 待立项说明（**只报告，未实现**）

### 5.1 能力缺口

| 现状 | 事实/锚点 |
|---|---|
| 唯一的「输入映射读者」是 `editor_get_input_actions` | 它读**编辑器进程**的 `InputMap` 单例 |
| 编辑器进程**永远不会**载入工程 `[input]` | `main/main.cpp:2330-2333`：`editor || project_manager` → `input_map->load_default()`；只有游戏分支走 `load_from_project_settings()`（`:2335`） |
| 因此它**看不到工程级真相** | TASK-041 §3.4 实测：一个**全新编辑器进程**的 `editor_get_input_actions` `count=89`，**不含**刚从磁盘写进去的动作 |
| 想确认「游戏能不能看到」目前只有一条路 | 起一个**游戏**进程，再 `running_game_execute_gdscript` 读 `InputMap` |

**缺口一句话**：调用方无法回答「**我的工程**里定义了哪些动作、各自绑了什么、这次写的到底落盘没有」——
除 `editor_add_input_action` 自己返回的 `persisted`/`project_entry`（只覆盖**刚写的那一个**动作）之外，
只能靠起游戏进程。

### 5.2 建议的工具名与签名草案（**草案，未实现**）

沿用 `project_*` 家族（本 fork 里 `project_*` = 工程/资源级、与进程角色无关，
如 `project_read_resource` / `project_get_export_info`）：

```
name:        project_get_input_map
channel:     both   (editor 9888 与 game 9889 都可用；两者都能读磁盘上的 project.godot)
verb:        read
scope:       project
mutating:    false
inputSchema: { "action": string, optional }        # 省略 = 列出全部
```

建议返回形状（**可链式喂回**，且与 `editor_add_input_action` 的写入口径一致）：

```jsonc
{
  "target": "project",
  "source": "/abs/path/to/project.godot",     // 实际读的文件
  "on_disk": true,                            // 文件存在且解析成功
  "count": 1,
  "actions": [                                // 与输入动作值同形：deadzone + events
    { "action": "mcp042_mirrored_action",
      "deadzone": 0.2,
      "events": [ { "type": "InputEventKey", "keycode": "J", "pressed": true } ],
      "event_count": 1,
      "entry": "project" }                    // project = 来自 [input]；未在工程里定义的内置动作不在此列
  ],
  "process_map": {                            // 可选、正交：本进程 InputMap 的对照，避免「两张表」混淆
    "action_exists": true,
    "event_count": 1,
    "source": "editor_load_default" | "game_load_from_project_settings"
  }
}
```

实现落点（若立项）：读者 = 用引擎自己的 `ConfigFile` 解析 `project.godot` 的 `[input]` 段
（`read_input_action_from_disk` 的读法可复用/泛化），**不依赖**进程映射——这正是「工程级」的含义。

### 5.3 影响面

| 面 | 影响 |
|---|---|
| 契约 | **+1 条**（171 → 172）→ `docs/tools_list.renamed.json`、`docs/tool-rename-map.json`（sha → `_meta.map_sha256` 指纹）、`docs/tool-groups.json`、`docs/tool-groups-b2.json` 全部要动；门① 的「并集逐字」断言随之变化 |
| 规范 | `docs/DESIGN-DETAIL.md` 的工具清单/契约指纹需要更新（**决策者维护**，本批未改） |
| 代码 | 新增 `tools/project_input_map.{h,cpp}`（或并入既有 project 组文件）+ `registration.cpp` 一行 + doctest（成功/缺参/工程无该动作/`[input]` 缺失/损坏文件） |
| 与 O-5 的关系 | 「删除动作」类工具（契约里目前**不存在**，REPORT-041 §4 已证）一旦立项，必须**同时**清 `input/<action>`；O-4 与 O-5 是同一家族的两半，建议**同批**裁决 |

### 5.4 建议

**单独立项、与 O-5 同批**；不要塞进 TASK-042 这类「不扩张契约」的批次。
若决策者认为「工程级输入映射」不是必要能力，则**至少**把 `editor_get_input_actions` 的**语义边界**
保持在契约描述里（它读的是编辑器进程的 map，不是工程的），这一点 TASK-041 已经钉过机器证据。

---

## 6. 门（真实输出与退出码）

### 6.0 门的绑定（R-1）

```
> modules\mcp_server\scripts\build_local.cmd -Force      (tests=yes，从 cmd 启动，串行，未抑制输出)
build_local: exit code = 0

> bin\godot.windows.editor.x86_64.console.exe --version
4.8.dev.custom_build.3b7a3c19b
> git rev-parse --short=9 HEAD
3b7a3c19b
```

包裹在 `scripts/mcp042_gates.ps1` 里串行执行（每步独立日志 + 退出码，**两个引擎从不同时启动**，
驱动**不调用 scons**）。原始日志：`docs/reports/evidence/task042/gates/summary.txt` 与 `*.log`。
**全 19 步 exit 0**：

| 步 | 门 | 退出码 | 耗时 |
|---|---|---|---|
| `gate3_module_doctest` | ③ 模块 doctest | **0** | 6s |
| `gate4_full_doctest` | ④ 全引擎回归 | **0** | 32s |
| `gate1_contract_subset` | ① 契约子集逐字（`-Group editor_input_simulation`） | **0** | 28s |
| `gate6a_narrowing` | ⑥ 收窄点清单 | **0** | 1s |
| `gate6b_narrowing_coverage` | ⑥ `--coverage` | **0** | 0s |
| `gate6c_coverage_probes` | ⑥ 拼写探针 | **0** | 52s |
| `gate5_accept_run1` / `run2` | ⑤ `accept_m1.ps1` ×2 | **0** / **0** | 49s / 49s |
| `gate2_rewrite_and_honesty_evidence` | ② 本批线上证据（§3/§4） | **0** | 21s |
| `gate2b_port_guard_probes` | ②（① 的探针证据） | **0** | 1s |
| `gate2c_task041_evidence` | ② 回归：TASK-041 证据链 | **0** | 29s |
| `regress_mcp032` | 回归（① 对齐后） | **0** | 10s |
| `regress_mcp033` | 回归 | **0** | 13s |
| `regress_mcp034` | 回归 | **0** | 15s |
| `regress_mcp035` | 回归 | **0** | 14s |
| `regress_mcp036` | 回归 | **0** | 23s |
| `regress_probe037` | 回归 | **0** | 9s |
| `regress_mcp040_probes` | 回归（`-Label task042`） | **0** | 25s |
| `regress_mcp040_racing` | 回归 | **0** | 47s |

`.ps1` 纯 ASCII：4 个新脚本与 6 个回归脚本非 ASCII 字节 = 0；`accept_m1.ps1` 的 22 个非 ASCII 字节是**既有**的
`§`，`git diff -U0` 的**新增行**经 `findstr /R "^+[\x80-\xFF]"` 检查为**零命中**（命令退出码 1 = 无匹配）。

### 6.1 ① 契约子集逐字（exit 0）

```
PASS  editor_9888_contract_subset   editor port=9888 tools=148
      editor_add_input_action: name=True description=True inputSchema=True
      （editor_simulate_input_action/key/mouse_click/mouse_move/input_sequence 六条全 True）
PASS  game_9889_contract_subset     game port=9889  tools=69
      editor_add_input_action: correctly absent on the game endpoint
PASS  guard_user_port_9877
group=editor_input_simulation tools=6 contract=171
3/3 checks passed
```

本批**没有动契约**（§1.3 的 sha256 与 REPORT-041 逐字相同），所以这条门测的是「改动没有漂移契约」：
`editor_add_input_action` 的 `inputSchema` 仍是 `{action: string, key?: string}`（**未新增参数**），
`description` 逐字未变；新增的 `action_state`/`project_entry` 是**响应**字段，不在契约对象里。

### 6.2 ③ 模块 doctest（exit 0）

```
[doctest] test cases:   277 |   277 passed | 0 failed | 1429 skipped
[doctest] assertions: 15948 | 15948 passed | 0 failed |
[doctest] Status: SUCCESS!
```

基线（TASK-041）= 277 用例 / 15919 断言；本批用例数不变，**断言 +29**（工具级用例 `216 → 227`，
TASK-041 帮助器用例 `41 → 59`），**0 failed**。

### 6.3 ④ 全引擎回归（exit 0）

```
[doctest] test cases:   1703 |   1703 passed | 0 failed | 3 skipped
[doctest] assertions: 440230 | 440230 passed | 0 failed |
[doctest] Status: SUCCESS!
```

基线 1703 / 440201；**断言 +29**（同上），**0 failed**。

### 6.4 ⑥ 收窄点三段式（GDR-24，三段全 exit 0）

* `check_narrowing_points.py` → **exit 0**：`scanned 73 / pinned 73`，`--coverage` 打印 **17 种已声明拼写**；
* `mcp031_gate6_coverage_probes.ps1` → **exit 0**：**101/101 checks passed**，且探针后源码 sha256 逐字节还原；
* 本批**没有新增任何收窄点**（`tool_helpers.cpp` 的改动只做 `Variant` 读取与比较，没有新的窄化写入），
  所以 PINNED 清单**不需要新增条目**。

> **如实记录一处遗留**：该工具报告 **11 条 pinned 行号漂移**（例：`tools/tool_helpers.cpp marker=G24-THE-GATE
> occurrence=0 pinned_line=1161 now=1466`），原因是本批在 `tool_helpers.cpp`/`editor_input_simulation.cpp` 等
> 文件里插入了新代码。脚本**自己**声明「the pin is by marker id + occurrence, so this is not a failure;
> update the list when convenient」。我**没有**去更新这 11 个行号：它不影响门的语义（仍在 exit 0 下全绿），
> 且在本批门批次开跑后修改门脚本会让「门的被测提交」失去意义。→ 见 §8.1 deviation 4 与 §8.3 risk 4。

### 6.5 ⑤ `accept_m1.ps1` ×2（exit 0 / exit 0）

```
22/22 cases passed          （run 1 与 run 2 逐字相同）
[PASS] guard_user_port_9877
       listening=False pid_before=-1 pid_after=-1 ours=False same_pid=True asked_by_us=False classification=environment_fact_no_listener_before_or_after
```

两次的 PASS 清单逐条一致，两次都 **22/22**。与 TASK-041 的差别只在 `accept_m1.ps1` 内新增的那一类判定
（本环境不触发，故行为不变）——**门⑤ 保持 22/22 ×2 全绿**（任务书 §1 的要求）。

### 6.6 ② 线上证据（exit 0）

* `mcp042_projectrewrite_and_honesty_evidence.ps1`：**30 checks, 0 failed**（§3、§4 的每一条都出自它的原始输出）；
* `mcp042_port_guard_probes.ps1`：**21 checks, 0 failed**（§2.3）；
* `mcp041_inputmap_persistence_evidence.ps1`（回归，确认 M-6 没被本批破坏）：**32 checks, 0 failed**。

三类证据齐备：成功路径（新建/幂等/内置镜像）、缺参/非法名（`mcp041.dotted` → `persisted:false` + 原因）、
底层失败（无 `project.godot` 的进程 → 诚实 `false` + 原因、且**不新建**文件）；端到端活证据链是
`editor_add_input_action` → `project.godot` 字节变化（sha256 逐字节级）→ **真实游戏进程** `InputMap.has_action=True`
（§3.4 的 `B11`–`B13`）。

---

## 7. 回归脚本群：逐条归因

与 §2.5 同一批数据，这里给出**逐条**收口（8 个脚本 + 1 个 TASK-041 证据链，全部 exit 0）：

| 脚本 | 检查数 | 结果 | 归因 |
|---|---|---|---|
| `mcp032_d3_d4_d6_evidence.ps1` | 38 | **38 / 0** | TASK-041 复跑时 38 PASS + 1 FAIL（9877 前置）；该 FAIL 已按 §2 消除 |
| `mcp033_b5_animation_evidence.ps1` | 74 | **74 / 0** | 同上（当时 74 + 1） |
| `mcp034_b5_audio_particle_theme_evidence.ps1` | 113 | **113 / 0** | 同上（当时 113 + 1） |
| `mcp035_b5_tilemap_shader_physics_evidence.ps1` | 66 | **66 / 0** | 同上（当时 66 + 1） |
| `mcp036_b5_navigation_theme_export_android_evidence.ps1` | 58 | **58 / 0** | 同上（当时 58 + 1，断言 id 是 `port_9877_guard_before/after`） |
| `probe037_d2_d1_r1r2.ps1` | 39 | **39 / 0** | 同上（当时 39 + 1） |
| `mcp040_defect_probes.ps1 -Label task042` | 47 | **47 / 0** | 本来就没有「必须有监听者」这一半（只断言前后一致），本批未改动它 |
| `mcp040_racing_regression.ps1` | 35 | **35 / 0** | 同上 |
| `mcp041_inputmap_persistence_evidence.ps1`（回归） | 32 | **32 / 0** | 证明 TASK-041 的 M-6 行为未被本批改变 |

**没有一个脚本出现「新回归」**；没有任何用例被删除而不被替代；每个脚本的 9877 证据行都在 §2.5 逐字列出。
（原始日志：`docs/reports/evidence/task042/gates/regress_*.log`。）

---

## 8. deviations / blockers / risks / next_step

### 8.1 deviations（与任务书/手册的显式偏离）

1. **多改了一处门⑤ 的判定**（任务书 §0.1 只点名 6 个回归脚本）：`scripts/accept_m1.ps1` 新增
   `user_editor_vanished_during_the_run` 一类。理由：直接照抄门⑤ 的六分类，会在「用户编辑器本来在、
   运行后不见了」这一格上**放松**旧断言（旧断言在这里是 FAIL）。任务书明确要求「**不得**放松真不变式」，
   因此两边都补了同一类；当前环境不触发它，门⑤ 行为不变（22/22 ×2，§6.5）。
2. **`action_state` 的「modified」判定用「本进程映射的事件数是否增加」**，而不是「调用方给了 `key`」：
   引擎的 `InputMap::_find_event()` 会拒绝重复事件，所以「给了 key」不等于「改了映射」。
3. **响应新增 2 个字段**（`action_state`、`project_entry`）——按任务书「不新增参数」执行：`inputSchema`
   零改动、`name`/`description` 零改动（§6.1 逐字 True）。响应形状从来不在 `tools_list.renamed.json` 里
   （TASK-041 已以同口径加过 `persisted_reason`）。
4. **没有更新门⑥ 的 11 条 pinned 行号**（§6.4 的遗留）。理由：脚本自己声明它不是失败；且门批次开跑后
   再改门脚本会让「门的被测提交」失效。
5. **`project.godot` 的「节/键可能被重排」只由源码判定，未实测**（§3.2 末段标注为推断）：
   本样本的节本来就是字典序。若决策者要一条实测，需要另造一个「节序被打乱」的工程样本。
6. **⑥ 的可行方案只 spike，未实现**（§3.4/§3.5）：任务书 §0.2 要的是「实测 + 结论」，且实现它等于改变
   写路径的风险面 + 可能牵动工具 `description` → 交决策者（§8.4）。
7. **`docs/tool-groups-b2.json` 的过期 `notes` 仍未改**（继承 REPORT-041 §4.3 的报缺陷项）；本批**未改**
   任何组清单/契约/映射（§1.3）。

### 8.2 blockers

**无**。9877 无监听者是**环境事实**（本批把它变成可读的分类，而不是失败）；所有门与回归均 exit 0。
唯一一次环境异常是 `--import` 首次尝试以 `0xC0000005`（退出码 `-1073741819`）结束，`mcp_import_guard.ps1`
的**有界重试**在第 2 次成功（evidence run 1 的日志在 `docs/reports/evidence/task042/` 里没有留存，
但该现象与 REPORT-028 的结论一致：间歇性、无法归因到本模块、纪律靠「校验 + 重试 + 诊断」兜住）。

### 8.3 risks（遗留风险，交给决策者）

1. **`project.godot` 会被整份重写、手写注释必丢**（§3.2/§3.3）——这是本批最值得记载的一条；
   现在它不只是 `project_set_setting` 的既有行为，而是**「加一个输入动作」的副作用**。
2. **契约里没有任何工具能读「工程级输入映射」**（§5）——`editor_get_input_actions` 读的是编辑器进程的 map。
3. **内置动作名会被镜像进工程**（`ui_accept`）——本批让这件事**可读**（`project_entry: "created"`），
   但**没有**决定它该不该发生（TASK-041 的 O-6 仍是「行为已实测、取舍未决」）。
4. **门⑥ 的 11 条 pinned 行号已漂移**（§6.4）——不影响 exit 0，但下次有人改这几个文件时会继续漂。

### 8.4 next_step_recommendation

1. **裁决 §3.5 的 ② 结论**：把「重写整份 `project.godot`、注释会丢」写进规范与该工具 `description`
   （需要一次显式的契约变更），或者授权立项「`[input]` 条目级拼接发布」helper（行为规格见 §3.4）。
2. **裁决 O-4 / O-5**（§5）：`project_get_input_map` 这类「工程级输入映射读者」+「删除动作要清 `input/<action>`」，
   建议同批立项。
3. **裁决 O-6**：内置名镜像进 `[input]` 是「有用的显式覆盖」还是「意外写入」。
4. **顺手清理**：下次动门⑥ 相关文件时，把那 11 条 pinned 行号刷新一次。

---

## 9. 结论锚点（D86）与证据清单

* **① 的结论**（§2）：脚本改动测自 `b72c09a3ea`；**复跑**测自 `3b7a3c19b1` 的二进制
  （`4.8.dev.custom_build.3b7a3c19b` == `git rev-parse --short=9 HEAD`）。可核对：
  `git show b72c09a3ea --stat`（10 个脚本文件）与 §2.4 的对照表。
* **② 的结论**（§3）：**实测**测自 `3b7a3c19b1` 的工作树与二进制；行为本体（是否重写、丢不丢注释）由
  `tools/tool_helpers.cpp` 的 `publish_project_settings_to`（TASK-041 引入，`36c485834e`）决定，
  本批**未改**写路径 —— 可核对 `git diff --stat 3b7a3c19b1 -- modules/mcp_server/tools/tool_helpers.cpp`
  只含 `[input]` **分类**代码，不含发布实现。
* **③ 的结论**（§4）：**行为**测自 `d5b98df19a`；**门与线上证据**测自 `3b7a3c19b1`。
  可核对 `git diff --numstat 3b7a3c19b1 HEAD -- modules/mcp_server/tools modules/mcp_server/tests`（本报告提交
  **不触碰**这两棵树 ⇒ 门的被测代码 == `3b7a3c19b1`，与 REPORT-040/041 同一种论证）。
* **④ 的结论**（§5）：**无代码**，只有本报告 §5 的待立项说明。
* **门⑥ 的三段式**（§6.4）：测自 `3b7a3c19b1` 的工作树（源码扫描，与二进制无关）。
* **本报告提交**：`10dfe36a69`，只加 `docs/reports/REPORT-042-*.md` 与 `docs/reports/evidence/task042/**`
  （**没有一个文件进入二进制**）；证据目录的字节保真是 `a502516976`（子树 `* -text`）与
  `8fb95f4208`（`--renormalize` 4 个 CRLF 文件）。**实测**（D86）：
  `git diff --stat 3b7a3c19b1 HEAD -- modules/mcp_server/tools modules/mcp_server/tests` **为空**
  ⇒ 门的被测代码 == 门批次提交 `3b7a3c19b1`；`git diff --numstat 3b7a3c19b1 HEAD -- modules/mcp_server/scripts`
  同样为空 ⇒ 门批次之后没有再改过门脚本。
  证据保真的核对方式是逐字的：
  ```
  > git cat-file blob HEAD:.../evidence/task042/rewrite/project-godot-rewrite-diff.txt > %TEMP%\mcp042\blob-check.txt
  > sha256(blob-check.txt) = 5035dd6a014c0231fc7df2f36ec3dd4feff4cd6c2fdca31ae75d261183209498
  > INDEX.md 记录的      = 5035dd6a014c0231fc7df2f36ec3dd4feff4cd6c2fdca31ae75d261183209498   （相同）
  > git cat-file blob HEAD:.../evidence/task042/gates/summary.txt  同理 == 6f919d6e…ccf49
  ```

原始证据（本报告内联的每一条都能在这里找到原文）：

| 位置 | 内容 |
|---|---|
| `docs/reports/evidence/task042/INDEX.md` | 41 个证据文件的**字节数与 sha256** |
| `.../task042/gates/summary.txt` | 门批次的逐步退出码（§6.0 的那张表） |
| `.../task042/gates/gate{1,2,2b,2c,3,4,5_*,6a,6b,6c}_*.log` | 各门的原始输出（含 `3/3`、`22/22`、`277/277`、`1703/1703`、`scanned 73 / pinned 73`、`101/101`、`30/0`、`21/0`、`32/0`） |
| `.../task042/gates/regress_*.log` | 6 个对齐脚本 + 2 个 mcp040 脚本的逐条 PASS/FAIL 与 9877 证据行 |
| `.../task042/rewrite/*.json` | 门② 的原始请求/响应体（`curl.exe -s -o` 落盘，逐条 sha256） |
| `.../task042/rewrite/mcp042-rewrite-summary.json` | 30 条检查的 id / pass / evidence |
| `.../task042/rewrite/project-godot-rewrite-diff.txt` | §3.2 的**逐行 KEPT/LOST** 清单 + 重写后的整份文件 |
| `.../task042/probes/mcp042-port-guard-checks.json` | 21 条 9877 分类探针的原始结果 |
| `.../task042/logs/red-A.log` | 红 A：4 条行为红断言的真实输出（§4.3） |
| `.../task042/logs/green-A.log` / `green-B2.log` | 绿：`227/227` 与 `59/59` |
| `.../task042/gates/gates-console.log` | 门驱动的控制台全文 |