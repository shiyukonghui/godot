# REPORT-073 — A：`precision=double` 作为**门③ 的可选变体**（B 部分留待 B 角色）

- **任务书**：`modules/mcp_server/docs/tasks/TASK-073-double-gate-and-handover.md`（**本报告只覆盖 A 部分**；B 的收口/移交文档由随后的 B 角色写入本文件或 `MCP-SERVER-HANDOVER.md`）
- **来源**：`REPORT-071` §B.4（「门③ 是单精度门、双精度未被任何门覆盖」+ 建议把 double 做成可选变体）、`REPORT-072`（锚点判据）
- **契约**：**176**（条数不变；两次门① 实况都是 `contract=176`，编辑器 **153** / 游戏 **72**，并集 **176**）
- **构建锚点（D86 ①）**：`9c12c2383` —— 双精度二进制自报 `4.8.dev.double.custom_build.9c12c2383`，与该次 `git rev-parse --short=9 HEAD` **逐字一致**（`ANCHOR_EQUAL`）。单精度二进制自报 `ff796dbf9`，对同一 HEAD 判 `ANCHOR_STRUCTURAL_EQUIVALENT`（35 个差异全是非编译输入）。两道门与全部证据都在这个锚点窗口内采集。
- **交付提交**：`9c12c23834`（实现）+ 报告/证据提交（见 §9）。**未 push**。
- **9877**：全程未占用、未杀、未重启 —— 两次门① 的 `guard_user_port_9877` 都是 **PASS**（`user editor on 9877 before run: pid=-1`），收尾 `netstat -ano` 在 **9877/9888/9889 上都没有监听**，也没有残留引擎/scons 进程。

---

## 0. 一句话结论

门③（`--headless --test --test-case="[MCPServer]*"`）**默认仍然是单精度门，默认步表逐条未变、默认时长未增、默认不构建任何东西**；
`precision=double` 成为它的**显式可选变体**（`mcp059_gates.ps1 -PrecisionVariant double`，等价 `-WithDouble`），
该变体**追加一步**：串行复用 `scripts/mcp070_build_double.cmd` 构建 `.double.` 二进制 → 用 TASK-072 的唯一锚点判据判锚点
（实测 `ANCHOR_EQUAL`，`STALE_COMPILED` 已用真实反例证红）→ 在它上面跑**同一个** `[MCPServer]*` 用例集并要求全绿
（实测 **345/345、23956/23956 断言**）。红相位没有被"说明不可构造"糊过去：用 `4512d14c7e` 的 **F-1 修复前**测试文件
**重放**了一次，重现了历史记录的 **345 | 338 passed | 7 failed、23961 | 23862 passed | 99 failed**，随后还原文件、重建、转绿（345/345）。
**没有放松任何断言**：用例集、判据、绿的标准都与门③ 完全相同。

---

## 1. 交付物

| 文件 | sha256 | 角色 |
|---|---|---|
| `scripts/mcp059_gates.ps1` | `b5eda4b09c35b401976a14dd625f06a4eba818f91da81f9d18fa8618c2de0d84` | **门③ 的驱动处**：`param` 加 `-PrecisionVariant single\|double`（默认 `single`）与 `-WithDouble`；默认步表**一行未动**；末尾追加**唯一**一个带标记 `MCP073-ONLY-IN-DOUBLE-MODE` 的 `Invoke-Step`（只在 double 时走到） |
| `scripts/mcp073_gate3_double.ps1` | `55254e01cfe20afecddc0797667a2c9856dea651b9a6c4bd90de39588d8ff37e` | **变体本体（一步完成）**：scons 并发预检 → 串行构建（复用 `mcp070_build_double.cmd`）→ 锚点判据 → 双精度 doctest 绿判定 → 单精度对照 → 落 `gate3_double_summary.txt` |
| `scripts/mcp073_gate3_double_red_phase.ps1` | `b706a63ffba0d864c438614ac9355712b57e6632628e3993ef97b7483a77facb` | **红相位重放**：把 `4512d14c7e` 的 pre-F-1 测试文件按**原始字节**写回 → 构建 → 必须红 → `git checkout` 还原（逐字节校验）→ 重建 → 必须绿 |
| `scripts/mcp073_default_plan_compare.ps1` | `bd74d214549ea490b1e1f1f9130d4b9a1dd1d147c2cc7f97351fa41708831d78` | **「默认路径逐项不变」的机器检查**：从 `git show <基线>:<路径>` 与工作树各抽取步表（名字 + **整行命令**），逐条比较；双模式必须只多一步 |
| `scripts/mcp073_plan_compare_probe.ps1` | `83c856f86709a38f269c2a4844a95bcebca2bf3a9695ca42cf111525f96f8f4a` | 上面那个检查的**插入探针**（插入一步 → 必须红；删掉带标记的一步 → 必须红；真文件逐字节未动） |
| `docs/tasks/PLAYBOOK-group-port.md` | 见 §6 | §3 门③ 那一行改成：**默认单精度门 / double 是显式可选变体 / 不给开关时步数与默认时长不变** |
| `docs/reports/evidence/task073/` | 见 §10 | 全部证据（绝对路径在 §10） |

**没有触碰的东西**：`docs/DESIGN-DETAIL.md`（**未改，见 §6 的建议文本**）、`tools/**`（0 行）、`tests/**`（不变；红相位脚本只在运行时临时写、随后逐字节还原）、契约/映射/生成器（0 改动）、hof-rs（只读）、`mcp057_gates.ps1`（**未改**，见 §5 的边界声明）。

---

## 2. 开关语义（默认与显式两条路，都不含糊）

| 调用 | 步数 | 是否构建 | 说明 |
|---|---|---|---|
| `mcp059_gates.ps1`（默认） | **22** | **否** | 与 TASK-059/072 的步表**逐条相同**（§3.1 机器证明） |
| `mcp059_gates.ps1 -PrecisionVariant double` | **23** | **是**（`.double.`） | 末尾追加 `gate3_double_variant`（`exit=0`） |
| `mcp059_gates.ps1 -WithDouble` | **23** | 是 | 与上面等价（同一开关的别名） |
| `... -WithDouble -PrecisionVariant single` | — | — | **互相矛盾 → usage error，exit 3**（不是"后者静默胜出"） |

- 默认路径**不新增任何输出行**：`precision variant: ...` 那一行只在 double 模式打印，因此默认模式的 stdout 除时间戳/日志路径外与改动前同形。
- 变体那一步在脚本里的**唯一**标记是 `MCP073-ONLY-IN-DOUBLE-MODE`；`§3.1` 的检查断言「整个驱动里只有这一行 `Invoke-Step` 提到 `mcp073_gate3_double.ps1`」。
- 变体脚本本身可独立运行（不经过电池）：`mcp073_gate3_double.ps1 [-SkipBuild] [-SkipSingleControl] [-ExpectCases N] [-AllowConcurrentBuild]`；`§4` 给了一次独立运行的结果（含单精度对照）。

---

## 3. 证据①：**默认路径逐项不变**（给对照）

### 3.1 静态机器检查（`mcp073_default_plan_compare.ps1`，6/6 PASS，exit 0）

基线取 `git show 8ffb92b4b:modules/mcp_server/scripts/mcp059_gates.ps1`（TASK-073 改动**之前**的提交），当前侧取工作树：

```
baseline default steps (22) = gate3_doctest_mcpserver ... t059_d2_failure_demo
current  default steps (22) = <逐字相同>
current  double-mode steps (23) = 上面 22 步 + gate3_double_variant
```

| check | 结果 |
|---|---|
| `g3p_baseline_read_from_git_is_a_gate_script` | PASS（7898 字节、22 步） |
| `g3p_default_default_plan_is_identical_in_order_and_content` | PASS（22 vs 22，顺序与名字相同） |
| **`g3p_default_step_lines_are_identical_arguments_included`** | **PASS**（22 条 `Invoke-Step` **整行**逐字比较，differing=0 —— 参数、引擎 flag、`--test-case=` 集合都没变） |
| `g3p_baseline_carries_no_double_only_step` | PASS（基线带标记步数 = 0） |
| `g3p_double_mode_adds_exactly_one_step_named_gate3_double_variant` | PASS（带标记 1 步、双模式比默认多**恰好 1** 步） |
| `g3p_the_variant_script_is_invoked_only_by_the_tagged_step` | PASS（驱动里只有那一行 `Invoke-Step` 提到变体脚本） |

证据：`evidence/task073/gate3_default_plan_compare.txt`（sha256 `7afa2bc4…`）、`gate3_default_plan_compare_stdout.txt`（`ea964971…`）。

**这个检查自己能被证红**（`mcp073_plan_compare_probe.ps1`，**4/4 PASS**，exit 0；红线输出当场保存在同一份转录里）：

| 探针 | 条件 | 结果 |
|---|---|---|
| P1 | 未改动的驱动 | 检查 exit **0**（绿的一侧） |
| P2 | 合成副本里**插入**一步 `Invoke-Step 'mcp073_probe_extra_step'` | 检查 exit **1**，点名 `g3p_default_default_plan_is_identical_in_order_and_content` **FAIL** |
| P3 | 合成副本里**删掉**带标记的 double 步 | 检查 exit **1**，点名 `g3p_double_mode_adds_exactly_one_step_named_gate3_double_variant` **FAIL** |
| P4 | 真驱动文件 | sha256 前后**逐字节相同**（探针只读它，合成副本在 `%TEMP%`） |

证据：`evidence/task073/gate3_plan_compare_probe.txt`（`b842d20d…`）、`gate3_plan_compare_probe_stdout.txt`。

### 3.2 两次完整电池实测（在锚点 `9c12c2383` 上）

| 运行 | 命令 | 步数 | 结果 |
|---|---|---|---|
| **不给开关** | `mcp059_gates.ps1 -LogRoot %TEMP%\mcp073\battery_default` | **22** | **`ALL GATE STEPS EXIT 0`**；22 步全部 exit 0 |
| **给开关** | `mcp059_gates.ps1 -PrecisionVariant double -LogRoot %TEMP%\mcp073\battery_double` | **23** | **`ALL GATE STEPS EXIT 0`**；22 步 + `gate3_double_variant` |

**22 个共有步骤的逐条比对**（`evidence/task073/battery_double_vs_default_shared_steps.txt`）：

- **名字或退出码差异 = 0**；`gate3_doctest_mcpserver`、`gate4_full_regression` 等 **17 步的 summary 尾部逐字节相同**；
- 5 步尾部只差**易变段**（各自的 `%TEMP%` 证据根时间戳；`rb2_failure_demo` 还把两次运行自己的未跟踪 stdout 文件当**记录**列出，REPORT-070 §4.2 已判定那是记录不是判据）；
- 开关多出来的那一步是 `gate3_double_variant`（exit 0）。

**与现状基线（REPORT-072 §5）逐项一致**（两次电池都如此）：

| 门/步骤 | 本次实测（两次电池**相同**） | REPORT-072 基线 |
|---|---|---|
| ③ 模块 doctest（单精度） | **345 \| 345 passed \| 0 failed \| 1429 skipped；23971 \| 23971 passed \| 0 failed** | 345 / 23971 |
| ④ 全引擎回归 | **1771 \| 1771 passed \| 0 failed \| 3 skipped；448218 \| 448218 passed \| 0 failed** | 1771 / 448218 |
| ⑥ 三段式 | `scanned=75 pinned=75`；`--coverage` exit 0；探针 **101/101** | 同 |
| 生成器三连 | `BYTES ADDED 8072`/`SHA256 0295cf86…`/`GENERATOR-VERSION 1.20.0` | 同 |
| ⑤ tautology | `TAUTOLOGY CHECK PASS`；`--probes` `18/18` | 同 |
| ② 契约 pre/post | `CONTRACT PRE/POST PASS` | 同 |
| ① 契约子集 | `contract=176`、`153/72`、`3/3 checks passed`（默认 + 4 组） | 同 |
| 其它 | `t059_section_switch 30/0`、`patch2_settings_publish 23/0`、`rb2/d5/d2` demo PASS | 同 |

### 3.3 对照：默认模式**根本没碰**双精度产物（最强的一条）

不给开关的那次运行前后，记录 `bin\godot.windows.editor.double.x86_64.console.exe` 与 3 个 `.double.` 目标文件的
`LastWriteTimeUtc|Length|路径`（`double_artifacts_before_default_run.txt` / `_after_default_run.txt`，两份 **sha256 相同** = `b293159a…`）：

- **5/5 行逐字节相同、differing = 0**（含 exe 的 mtime —— 只要发生过一次构建/重链接就不可能相同）；
- 默认那次 LogRoot 里**没有** `mcp070_build_double.log`，也**没有** `gate3_double` 证据目录（都只在 double 模式创建）。

**边界（诚实声明）**：我证明的是「步表逐条相同（含整行命令）+ 每个步骤退出码相同 + 与记录基线数字相同 + 双精度产物零触碰」，
**不是**「两次电池 stdout 逐字节相同」——后者不可能也不必要（每次运行都打印自己的时间戳与 `%TEMP%` 日志路径）。

---

## 4. 证据②：给开关时的双精度结果

### 4.1 电池里的那一步（`-PrecisionVariant double`）

```
=== gate3_double_variant ===
    exit=0 :: checks : 8 failures 0 | GATE3_DOUBLE_VARIANT RESULT=PASS cases=345/345 assertions=23956/23956
              anchor=ANCHOR_EQUAL build_seconds=63.8 doctest_seconds=14.4 | GATE 3 DOUBLE VARIANT PASS
```

### 4.2 变体**独立**运行（终版脚本，含单精度对照；9/9 PASS，exit 0）

| 项 | 实测 |
|---|---|
| 构建 | `scripts\mcp070_build_double.cmd`，**exit 0**，**62.5 s**（20:06:22 → 20:07:24） |
| 双精度 doctest | `[MCPServer]*` → **exit 0；345 \| 345 passed \| 0 failed \| 1429 skipped；23956 \| 23956 passed \| 0 failed**，**14.5 s** |
| **单精度对照**（同一用例集） | exit 0；345 \| 345 passed \| 0 failed；**23971 \| 23971 passed \| 0 failed**，14.1 s |
| **锚点 verdict** | **`ANCHOR_EQUAL`**（`anchor=9c12c2383 head=9c12c2383 diff_count=0 red_count=0`） |
| 单精度二进制 | 构建前后 sha256 **相同**（`4b269370…`）——double 构建没有动它 |
| 时长 | 变体那一步合计 ≈ **77 s**（构建 62.5 + 双精度 doctest 14.5，热对象缓存下的增量；冷构建约 15 min，见 REPORT-071 §B.4） |

断言数差 **15**（单 23971 / 双 23956、用例数两边都是 345）与 REPORT-071 §B.3 的记载一致：那是 `if (sizeof(real_t) == 4)`
两条分支的**固有**差异，不是删断言。证据：`gate3_double_summary.txt`（`b8bfead8…`）、`gate3_double_doctest.txt`（`dbf0b439…`）、
`gate3_single_control_doctest.txt`、`gate3_double_variant_stdout.txt`。

### 4.3 四次双精度构建（**严格串行**，START/END 互不重叠）

| # | 触发 | 日志 | START | END | exit | 秒 |
|---|---|---|---|---|---|---|
| 1 | 开关电池的 `gate3_double_variant` | `mcp070_build_double_switched.log` | 19:48:57.87 | 19:50:01.48 | 0 | 63.6 |
| 2 | 红相位（pre-F-1 测试文件） | `mcp070_build_double_red_phase.log` | 19:59:20.54 | 20:00:30.70 | 0 | 70.2 |
| 3 | 红相位（还原后重建） | 同上（第二窗口） | 20:00:52.63 | 20:01:58.00 | 0 | 65.4 |
| 4 | 变体独立运行 | `mcp070_build_double_standalone.log` | 20:06:22.25 | 20:07:24.53 | 0 | 62.5 |

- 全部**从 `.cmd` 启动**、**不抑制输出**（`MCP070` 自带 `MCP_BUILD_LOG` 落盘 + 控制台，变体再打印日志尾部）；
- 全部**只有一个 scons**（D62）：变体在构建前做 scons 进程预检，多进程存活即**拒绝构建**（exit 4，`-AllowConcurrentBuild` 才可越过）；
- 与 TASK-071/072 的历史窗口（17:41–17:54、18:41–18:53）也**不重叠**。

---

## 5. 证据③：**红相位**（不是"说明不可构造"，是真做了一次）

### 5.1 重放 pre-F-1（`mcp073_gate3_double_red_phase.ps1`，**13/13 PASS**，exit 0）

方法：`git show 4512d14c7e:modules/mcp_server/tests/test_mcp_server.h` **按原始字节**写回工作树（`4512d14c7e` 是
F-1 修复前的提交，且 `4512d14c7e..HEAD` 里**只有这一个编译输入**，所以只还原它就精确复现 pre-F-1 状态），
校验 `git hash-object(工作文件) == git rev-parse(4512d14c7e:<路径>)`（`91075751…`，1 271 905 字节），构建、跑门③ 用例集。

| 项 | 重放实测 | 历史记录（`evidence/task071/doctest_module_double_RED.txt`） |
|---|---|---|
| 用例 | **345 \| 338 passed \| 7 failed \| 1429 skipped** | 同 |
| 断言 | **23961 \| 23862 passed \| 99 failed** | 同 |
| 失败用例数/名 | 7（与 REPORT-071 列的 7 条逐字一致，off-class = **0**） | 同 |
| 点名 `FLOAT32` 的 ERROR 行 | **0**（FLOAT32 槽是无条件编译的，D-15） | 0 |
| 点名 `REAL_T` 的 ERROR 行 | 20 行（REPORT-071 记的是"文本出现 22 处"，**计数口径不同**：行数 vs 出现次数，两者都指向同一批断言） | — |

随后 `git checkout HEAD -- <路径>` 还原：**sha256 回到起点**（`0c8b180f…`）、`git hash-object == HEAD blob`（`c30e61a0…`）、
`git status --porcelain` 为空；重建后同一用例集 **345/345、23956/23956、exit 0**，且与历史绿证据
（`doctest_module_double_GREEN.txt` 的 345 / 23956）**逐字相同**。最后 `g3r_final_state_is_untouched` 再次断言文件 sha256、
blob、porcelain、HEAD 全部回位。红/绿**原始输出当场保存**：`gate3_double_red_phase_RED.txt`（141 858 字节，`5c015b11…`）、
`gate3_double_red_phase_summary.txt`、`gate3_double_red_phase_failing_cases.txt`、`gate3_double_red_phase_stdout.txt`。

### 5.2 `STALE_COMPILED` **必须红**（真实反例，不需要任何虚构）

**本批开工时**双精度二进制自报的就是 `4512d14c7e`，而 HEAD 已经越过一个编译输入
（`modules/mcp_server/tests/test_mcp_server.h`）。用同一个判据直接判：

```
ANCHOR_JUDGE VERDICT=ANCHOR_STALE_COMPILED
ANCHOR_JUDGE ANCHOR=4512d14c7e HEAD=9c12c2383  ANCESTOR=yes
ANCHOR_JUDGE DIFF_COUNT=79 SAFE_COUNT=78 RED_COUNT=1
ANCHOR_JUDGE RED COMPILE_INPUT modules/mcp_server/tests/test_mcp_server.h
ANCHOR_JUDGE RESULT FAIL        → 进程 exit 非 0
```

证据：`anchor_stale_compiled_probe.txt`（`630a231b…`，含 `ANCHOR_PROBE_EXIT_NONZERO` 一行）。
**同一次对照**：单精度二进制（`ff796dbf9`）对同一 HEAD 判 `ANCHOR_STRUCTURAL_EQUIVALENT`（35 个安全差异、0 红）——
这正是"门③ 单精度不需要重建、双精度变体必须先构建"的**机器可验证理由**。

### 5.3 变体自己的失败传播（红 → 非零退出）

`mcp073_gate3_double.ps1 -SkipBuild -SkipSingleControl -ExpectCases 346`（故意把基线抬到 346）：
`g3d_double_doctest_case_count_not_below_the_baseline` **FAIL** → `GATE3_DOUBLE_VARIANT RESULT=FAIL`、
`GATE 3 DOUBLE VARIANT FAILED: 1`，进程 **exit 非 0**（`variant_red_probe.txt` 里 `VARIANT_PROBE_EXIT_NONZERO`）。
这一次探针里其它 7 项（含锚点 `ANCHOR_EQUAL`）仍为 PASS —— 说明红的只是那一条被故意做红的判据。
该探针还留下了一条清晰的 `build SKIPPED (-SkipBuild): ... this mode does NOT satisfy the serial-build requirement` 证据行。

---

## 6. 证据④：口径写进哪里（PLAYBOOK 已改；DESIGN-DETAIL **未改**，建议文本如下）

**已改**：`docs/tasks/PLAYBOOK-group-port.md` §3 第③ 行（原为「全绿（基线见上一份报告，只允许增加）」），现在写明：
门③ 默认是**单精度门**（跑 `bin\godot.windows.editor.x86_64.console.exe`）；`precision=double` 是**显式可选变体**
（`mcp059_gates.ps1 -PrecisionVariant double` / `-WithDouble` 才**追加一步** `gate3_double_variant`：串行复用
`mcp070_build_double.cmd` → `check_engine_anchor.ps1` 判锚点（`ANCHOR_EQUAL`/`ANCHOR_STRUCTURAL_EQUIVALENT` 通过、
`ANCHOR_STALE_COMPILED` 必须红）→ 在 `.double.` 二进制上跑**同一个** `[MCPServer]*` 用例集并要求全绿）；
**不给开关时步数、结果与默认时长逐项不变、不构建**，因此**双精度仍未被默认门覆盖**；并指向本报告。

**未改（按任务书要求报告给决策者）**：`docs/DESIGN-DETAIL.md`。建议落点与文本（决策者落笔）：

1. **§16「执行顺序修订」，第 3 条（`DESIGN-DETAIL.md:318-321`）**，把
   `③引擎 doctest 全绿；` 扩写为：
   > ③引擎 doctest 全绿（`--headless --test --test-case="[MCPServer]*"`）。**这是单精度门**（`precision` 缺省）。
   > `precision=double` 是它的**显式可选变体**（`scripts\mcp059_gates.ps1 -PrecisionVariant double` / `-WithDouble`）：
   > 该开关**追加一步**（串行构建 `.double.` 二进制 → 用唯一锚点判据判锚点，`ANCHOR_EQUAL`/`ANCHOR_STRUCTURAL_EQUIVALENT`
   > 通过、`ANCHOR_STALE_COMPILED` 必须红 → 在同一用例集上要求全绿）。**不给开关时不得构建、不得增加默认时长**；
   > 因此**双精度不在默认门覆盖内**，只有显式启用变体时才被覆盖（证据：`REPORT-073` A）。
2. 可选：新增 **GDR-29「门③ 的精度维度」** 一条，与 §22.3（门⑥ 的声明边界）同形，明确"默认门 = 单精度"是**声明过的边界**，
   而不是可以含糊的默认值。若决策者同意，建议同时把「变体开关是唯一入口、默认路径不得被改动」这句写进去。

---

## 7. 纪律清单

| 要求 | 状态 |
|---|---|
| 只改 `modules/mcp_server/**`；hof-rs 只读 | ✅ 改动只落在 `modules/mcp_server/{scripts,docs}`；hof-rs 未写 |
| 契约 176 条数不变 | ✅ 两次门① `contract=176`；未动契约/映射/生成器 |
| 不改 `DESIGN-DETAIL`（要改先报） | ✅ **未改**；建议文本见 §6 |
| 绝不占用/杀/重启 9877 | ✅ 两次门① `guard_user_port_9877` PASS（`pid=-1`）；收尾 netstat 无 9877/9888/9889 监听 |
| 端口 9888/9889 | ✅ 只由门①/门② 的既有脚本使用；无残留引擎进程 |
| 禁止 push | ✅ 未 push |
| **构建严格串行**、从 cmd 启动、不抑制输出 | ✅ 四次构建窗口互不重叠；scons 并发预检；全部 `.cmd` + `MCP_BUILD_LOG` 落盘 |
| 关键改动建提交 | ✅ `9c12c23834`（实现+PLAYBOOK+证据①）；报告/证据提交见 §9 |
| `.ps1` 纯 ASCII | ✅ 5 个脚本非 ASCII 字节数全为 **0**；全部 PowerShell AST 解析 0 错误 |
| 红相位输出**当场保存** | ✅ `gate3_double_red_phase_RED.txt`、`anchor_stale_compiled_probe.txt`、`variant_red_probe.txt`、`gate3_plan_compare_probe.txt`（含 P2/P3 的红） |
| 结论按 D86 标锚点 | ✅ 全文结论标 `9c12c2383`（构建/门/红相位）与 `8ffb92b4b`（§3.1 的基线侧） |
| 产物绝对路径 | ✅ 报告与 §10 全部为绝对路径 |
| 断言未被放宽 | ✅ 用例集/判据/绿标准与门③ 完全同一；新增的是**开关**与**证据**，没有改任何断言或 gate 语义 |
| 门相关脚本归因 | ✅ 两次完整电池的每一步都列出 exit（§3.2）；唯一非零不在本批（无） |

---

## 8. deviations / 已知边界 / blockers / next step

### 8.1 deviations（逐条显式）

1. **变体脚本在开关电池跑完之后被改过一处纯文案**：`-SkipBuild` 分支的证据字符串（原来会打印 `build exit = -1`）。
   改动范围：`mcp073_gate3_double.ps1` 中 `$buildEvidence` 的 `if ($SkipBuild)` 那一支（4 行）。
   **没有触及开关电池实际走到的分支**：同一 check 在两次运行里的证据行除秒数外逐字相同（§10 的
   `gate3_double_summary_battery_run.txt` vs `gate3_double_summary.txt` 已把两行并排给出）。任何后续复跑都用终版脚本。
2. **`mcp073_default_plan_compare.ps1` 在 `9c12c23834` 之后被加强过一次**（新增「整行命令逐条相同」这一 check，并把两侧步表写进工件）。
   该脚本**不参与电池**，其基线侧来自 `git show`，所以在终版上重跑得到的是同一结论（6/6 PASS，§3.1）；工件已按终版重生成。
3. **变体的日志落点**：驱动只传 `-EvidenceDir <LogRoot>\gate3_double`，变体自己的 `-LogRoot` 仍缺省到
   `%TEMP%\mcp073\gate3-double\<stamp>` —— 于是 `gate3_double_summary.txt` 落在电池日志目录，而原始 doctest/构建日志落在变体自己的戳目录。
   两条路径都会打印。**没有去"顺手改"，因为改 1 行会作废已采集的开关电池证据**；本次把需要的产物都已复制进 `docs/reports/evidence/task073/`。
   记为已知小疙瘩（后续若要修：驱动传 `-LogRoot (Join-Path $LogRoot 'gate3_double')` 即可）。
4. **`-SkipBuild` 模式的控制台汇总块仍打印 `build : exit=-1 seconds=0`**（其上的 check 行已明确写 `build SKIPPED ... does NOT satisfy the serial-build requirement`）。
   同上，为不使已采证据失效而保留；`-SkipBuild` 本来就是"重判盘上二进制"的便利模式，不满足串行构建要求。
5. **`-ExpectCases` 的判据是 `>=` 而不是 `==`**（默认 345）：允许后续批次**增加**用例、不允许**减少**（与 PLAYBOOK §3「只允许增加」一致），
   实际数字每次都会打印并落盘。本批实测 345/345。
6. **多做了一次独立运行**（§4.2）：为了让终版脚本的产物与 §4.1 的电池产物都可核对，我在电池之后又独立跑了一遍变体（含单精度对照，多一次 62.5 s 构建）。
   这是**成本披露**，不是偏离。
7. **`check_hardcoded_counts.py` 在既有文件上报 2 行 UNCLASSIFIED**（`scripts/mcp071_gate2_live_evidence.ps1:192,266` 的 `176`），
   与本批无关（该文件本批 0 改动），且该脚本**不在任何电池里**。我用它确认了新增的 4 个脚本**没有**引入任何未分类硬编码数字后报告在此。

### 8.2 已知边界（诚实声明，不夸大）

1. **变体是 opt-in 的**：`mcp059_gates.ps1` 的开关只影响这一个驱动；`mcp057_gates.ps1`（另一个门运行器）**未加**该开关，
   任何不传开关的批次**仍然没有双精度覆盖** —— 这是任务书明确要求的默认行为，也是移交时必须写下的边界（B 部分 §3⑩）。
2. **锚点判据是"拼写可见"的有界保证**（继承 TASK-072 §11.2）：它看 `git diff` 的路径，不看内容；一个不经 diff 体现的编译输入、
   一个由 `.json` 驱动的代码生成都在集合外。变体没有削弱也没有加强它，只是**复用它**。
3. **`-ExpectCases 345` 是一个基线字面量**：未来若有人删用例会被这条抓红；若有人加用例则通过（并打印新数字）。
4. **变体的串行保证是"预检 + 纪律"**：它在构建前检查存活 scons 进程并拒绝；理论上仍存在"同一瞬间另起一个 scons"的竞态，
   所以 D62 的"不要并发跑两个 scons"仍然是人的纪律，机器只把它变得**可失败**。
5. **红相位脚本会临时改写一个受版本控制的编译输入**（`tests/test_mcp_server.h`）：它有前置条件（该文件必须与 HEAD 逐字节一致）、
   `try/finally` 还原、还原后的 sha256/blob/porcelain 三重校验；**但**若进程被硬杀（不是正常退出），树可能停在 pre-F-1 版本上 ——
   这是该脚本唯一残留风险，使用前请确认工作树干净（脚本自己也会先拒绝）。
6. **`REAL_T` 行数口径差异**（我 20 行 vs REPORT-071 的"22 处文本"）：两者是不同计数方式，不是证据冲突；7 条失败用例名逐字一致。

### 8.3 blockers

**无。** 没有需要用户协助的环境/网络/权限问题。

### 8.4 next step（给决策者）

1. **写 DESIGN-DETAIL**：§6 的建议文本（§16 第 3 条③ + 可选 GDR-29）。决策者落笔，我不改。
2. **B 部分（收口/移交文档）**仍待做，其 §3 必须包含「门③ 默认是单精度门、双精度为可选变体；不给开关时不覆盖」（本报告 §0/§2/§8.1 已给可引用的事实与锚点）。
3. **是否把该开关同时接到 `mcp057_gates.ps1`**：本批按任务书只在 `mcp059_gates.ps1`（两个电池的并集版）落点；
   若要两个都通，是 3 行改动 + 一次重跑。
4. **是否把变体变成默认**：不建议按现状默认（冷构建 ~15 min，违背"默认不增加时长"）；若要定期覆盖双精度，建议做成独立 CI 步骤或每周一次，而不是塞进默认电池。
5. **`check_hardcoded_counts.py` 的 2 行 UNCLASSIFIED**（§8.1.7）是既有小债务，建议单开一个小批次处理。

---

## 9. 提交

| sha | 一行说明 |
|---|---|
| `9c12c23834` | `feat(mcp_server): TASK-073 A gate 3 precision=double optional variant (opt-in step, serial build, anchor judged, plan-compare probe)` —— 5 个脚本 + PLAYBOOK §3 门③ 行 + 任务书 + 证据① |
| `1ab3c14831` | `docs(mcp_server): TASK-073 A report, evidence and the argument-level default-plan check` —— 本报告 + `docs/reports/evidence/task073/**`（35 个文件）+ 计划比较的整行加强（`mcp073_default_plan_compare.ps1`）+ `mcp073_gate3_double.ps1` 的 `-SkipBuild` 文案（§8.1.1） |

> **锚点与报告提交之间只隔 `scripts/**`+`docs/**`（全是非编译输入）**：因此报告提交之后**不需要重建任何二进制**——
> 双精度二进制留在 `9c12c2383`（对报告提交后的 HEAD 会自然变成 `ANCHOR_STRUCTURAL_EQUIVALENT`，这正是 TASK-072 买来的性质）。
> 本报告的最后一处回填（补这一行的 sha）也是一个 `docs-only` 提交，所以 `git rev-parse --short=9 HEAD` 永远比本文件写下的 sha 新一截；这不是漂移。

---

## 10. 证据清单（绝对路径均在 `F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task073\`）

| 文件 | bytes | sha256 |
|---|---|---|
| `gate3_default_plan_compare.txt` | 10426 | `7afa2bc490ecf533dc874530c4b0c028bdb1709dc2fb1c6c004a08719025a4d4` |
| `gate3_default_plan_compare_stdout.txt` | 3729 | `ea964971b5d7ef9c6f05023ba77146279cc10f361dcc59908e5fbb3af75cfaf7` |
| `gate3_plan_compare_probe.txt` | 13197 | `b842d20da12f63642f485491d42b4a8298889a92195510f3cd6f77821745c107` |
| `gate3_plan_compare_probe_stdout.txt` | 1580 | `67e1e1a854ee8dd90161bbb99f3dd5d70f8d626c184f020fc7789e50a5eac1c8` |
| `battery_default_summary.txt` | 5193 | `aa9af5890396188b89ac54f467dd79fb9c582025f020ca12263c90ac8cf68839` |
| `battery_default_stdout.txt` | 14134 | `ef409c82a89b4477df56301bfc9385fc828865932ed15112f1805c7f070cc111` |
| `battery_double_summary.txt` | 5086 | `e2d5a86d30a9f4c6d52f0f13076e3c16bd3a43933532f52e3678be4354e98260` |
| `battery_double_stdout.txt` | 14036 | `88194ac0b1b85d39d6aec5aca8be0324238e8cfacd95337f3dff2ca262b5c65d` |
| `battery_double_vs_default_shared_steps.txt` | 3734 | `75636075c739d9a28b271d406ce8a1f8ee94e60d4a34ebe18b5b343ca19ffe63` |
| `double_artifacts_before_default_run.txt` / `_after_default_run.txt` | 696 / 696 | `b293159af0be2dc185b99989ada325815f5747459536eda1102f8245a2ed0100`（**两份相同**） |
| `gate3_double_summary.txt`（终版独立运行） | 4051 | `b8bfead81915fbb63137a785a311d1b9266e6cbea173ea33bd0325f872c9861b` |
| `gate3_double_summary_battery_run.txt`（开关电池里那一步） | 3766 | `b4bd8e19a10e77a6304ccc338a914bf64f9b0ba2f5b5aca8aa6780e62748f27f` |
| `gate3_double_doctest.txt`（双精度 345/345 原始输出） | 102044 | `dbf0b439ff35105a85e8bb9c1c85325148dd72860296cef172cb80ce2fbe038e` |
| `gate3_single_control_doctest.txt`（同一用例集单精度） | 102030 | `d5e91d49e6b66288c867e619ab4bf4eac2e243a5cc7272f2ec6bb9219b22e47e` |
| `gate3_double_variant_stdout.txt` | 4866 | `47b68b5424c53cef65d2a82de1f9de625eb6439ffdf2d73c42adc87d6944a8e2` |
| `gate3_double_red_phase_RED.txt`（**红相位原始输出**） | 141858 | `5c015b11ab891dc6a47179b9af5094a5bc9854820950cf6ad40f82d138e36edc` |
| `gate3_double_red_phase_summary.txt` | 5060 | `d8f5bb990f2e35285130d45b69abbff53f4ee8671e3e6be164ceb131227c8a83` |
| `gate3_double_red_phase_failing_cases.txt` | 941 | `7bfdde091705dd3a8c7e918b7aa192abb809e4e9dd8474be0bf5c2e343df505f` |
| `gate3_double_red_phase_stdout.txt` | 5850 | `cef8bfa9936fbc7d81207e84a3958e2497a1e84869ed22f430022fc7b32801cd` |
| `anchor_stale_compiled_probe.txt`（`ANCHOR_STALE_COMPILED` 真实反例） | 13689 | `630a231b20886ced07f4b602065071672012b681fbb947aaa798abd48c953208` |
| `variant_red_probe.txt`（变体自身红 → 非零退出） | 3889 | `c205e351b7eb50d53443a5992db1bba1ad0d249195fa26dbad5b33ae2c9447c1` |
| `mcp070_build_double_switched.log` | 3092 | `5b76f77ff64930b0b87aad6827ee44560669ed29d5363441382725ba1cdbf2cb` |
| `mcp070_build_double_red_phase.log` | 4718 | `a65cf36bc329718600a036da032444074860ccfb47b2927e41fddd6368f3890d` |
| `mcp070_build_double_standalone.log` | 2315 | `91e8c675393561da80131918ff98239e18477a63d77dac3d3f9fad53ad010125` |
| `build_windows.txt` | 918 | `96f27c1962d0a2470832c7140c5b7bb263fa4247842cf50002eec63cae4e6fee` |
| `port_9877_discipline.txt` | 497 | `9121bdce46f924ad082b6b8ba2e8cd0556f826bdac31f970ae857c48d370b96c` |
| `final_state_and_anchor.txt` | 4046 | `e030000242cbdf31bf9c7590b883d80e15a6b30101f7e48825c376e745db8407` |
| `head_before_batteries.txt` / `porcelain_after_double_run.txt` | 148 / 0 | `6e3df00e0d1b8525465346193c20de13e6f9dab7374bf9c5284875e77ebf4e2d` / `e3b0c442…`（空） |
| `hashes.txt` | — | 本次全部证据文件与脚本/二进制的 sha256 汇总（目录清单的**权威版本**；`battery_double_vs_default_shared_steps.txt` 与 `port_9877_discipline.txt` 的 sha256 在里面） |

- 二进制：双精度 `116fdfef92bdd2c5cf7e5c75bd5bf48b9c8f48bce8aeabe11492290698c12536`（300 544 bytes）；
  单精度 `4b269370db8ac449f1246657cf1daa331ec61d95c81f18ee468db08acd371331`（300 544 bytes，**与 REPORT-072 记录的完全相同 → 本批逐字节未动它**）。
- 开关电池的逐步 `.log`（UTF-16）与变体的原始戳目录在 `C:\Users\wyl\AppData\Local\Temp\mcp073\{battery_double,battery_default,gate3-double,gate3-double-red,variant_final,probe_expect_cases2}\`（`%TEMP%`，已在 §10 复制关键项入库）。

---

# B 部分 — 收口/移交文档（B 角色，锚点 `[sha:b6fbb917b]`）

> 本节由 **B 角色**追加（append-only；A 部分全文未改动一行）。B 的产物是**文档**，
> 不涉及任何实现改动。

## B.0 元信息

| 项 | 值 |
|---|---|
| 产物（绝对路径） | `F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\MCP-SERVER-HANDOVER.md` |
| 写作锚点（D86） | **`b6fbb917b`**（写作时的 `git rev-parse --short=9 HEAD`；= A 的两个 `docs/**` 提交之后） |
| 契约 | **176** 条不变，sha256 `701539829ed8fcaa227f280fb6bff71b96522248cd9c4b84f2073c27eb17cfe0`（155 872 B）—— 与 TASK-068 记录的 sha **逐字相同**，即本批**没有**动契约 |
| 端口 | 本批**没有启动任何引擎进程**（全部命令为只读：python 检查器、`--version`、锚点判据、`git`、文件哈希）→ 未占用 9888/9889，更未碰 **9877** |
| 构建 | 本批**没有运行 scons**（未构建；因此「严格串行」由「零构建」平凡满足） |
| 提交 | **未 push**；B 的产物是 `docs/**` 下的两份文档（本文 + `MCP-SERVER-HANDOVER.md`），**非编译输入**，不要求重建二进制 |

## B.1 六节是否齐（对照 TASK-073 §B.1–§B.6）

| 要求 | 本文档位置 | 齐 |
|---|---|---|
| ① 交付物清单（176 = 171 移植 + 5 新增；三个引擎补丁各一行目的 + `文件:行` + 为什么；HTTP/JSON-RPC 契约；mono 与非 mono 构建；端口规则 9877 用户 / 9888 编辑器 / 9889 游戏） | `MCP-SERVER-HANDOVER.md` §1.1–§1.5 | ✅ |
| ② 门与纪律（六道门 + 门完整性六条纪律：恒真断言 / 假等待 / 静默覆写 / 删证据 / 内红必须非零 / 锚点不得假红，每条一句话「防的是什么」+ **反例演示脚本路径**） | 同上 §2.1–§2.3 | ✅ |
| ③ 已知边界与已声明限制（(a)..(j) **完整**） | 同上 §3（(a)–(j) + §3.11 补充 11 条） | ✅ |
| ④ 复现步骤（从零到跑通六道门的最小集，含从 cmd 启动、串行约束、端口约束） | 同上 §4（12 步命令 + 只读实跑数字表） | ✅ |
| ⑤ 仍未做/被否决项（D-7 原子替换、`editor_reload_plugin` 节级化、`project.godot` 拼接器、9 条不建议项、F-066-3 …，各一句理由） | 同上 §5.1–§5.4 | ✅ |
| ⑥ 自检（每条断言可按复现步骤验证或按证据路径核对；**不得**有无锚点结论） | 同上 §6 | ✅ |

## B.2 已知边界条数

- **必需项：(a)..(j) = 10 条**（任务书 §B.3 点名的十项，逐条对应，无缺项）。
- **补充项：§3.11 = 11 条**（锚点判据的有界性、`UNCLASSIFIED` 保守选择、`STRUCTURAL_EQUIVALENT` 是推断非验证、
  变体的串行只是「预检 + 纪律」、红相位脚本的硬杀残留风险、`-ExpectCases` 的 `>=` 判据、变体日志落点小疙瘩、
  `check_hardcoded_counts.py` 的 2 行 UNCLASSIFIED、`!cmdline_mode` 守卫、历史报告 sha256 过期、`restored=57 vs 56`）。
- **合计 21 条**，每条都带 `[sha:…]` / `[文件:行]` / `[报告:… §x]` 锚点。

## B.3 复现步骤是否自洽（我自己跑过的只读核对，全部在 `[sha:b6fbb917b]`）

复现步骤的每一步都指向**仓库内存在的脚本**（`build_local.cmd`、`check_engine_anchor.ps1`、
`check_contract_subset.ps1`、`mcp071_gate2_live_evidence.ps1`、`mcp056_regression_battery.ps1`、
`check_narrowing_points.py`、`mcp031_gate6_coverage_probes.ps1`、`check_tool_groups.py`、
`check_tautologies.py`、`check_exit_propagation.py`、`mcp059_gates.ps1`、`mcp057_build_mono.cmd`、
`mcp070_build_double.cmd` —— 全部由 `[文件:modules/mcp_server/scripts/]` 目录清单核对）。
其中**不需要端口、不需要构建**的那一部分我**当场实跑**过，结果与文档写下的数字逐条一致：

| 命令（只读） | 实测 | 退出码 |
|---|---|---|
| `python modules\mcp_server\scripts\check_tautologies.py` | `TAUTOLOGY CHECK PASS`；`DECLARED SPELLINGS : 9 powershell + 5 python`；`PINNED: 1` | **0** |
| `python modules\mcp_server\scripts\check_tautologies.py --probes` | `PROBES: 18/18`（14 declared + 4 near-miss） | **0** |
| `python modules\mcp_server\scripts\check_exit_propagation.py` | `EXIT-CODE PROPAGATION CHECK PASS`；shapes 2 PS + 1 py、guards 10 PS + 6 py、`PINNED: 2` | **0** |
| `python modules\mcp_server\scripts\check_exit_propagation.py --probes` | `PROBES: 10/10` | **0** |
| `python modules\mcp_server\scripts\check_narrowing_points.py` | `scanned=75 pinned=75`（16 个文件）；18 条**行号漂移提示 = 非失败** | **0** |
| `python modules\mcp_server\scripts\check_narrowing_points.py --coverage` | **17 种已声明拼写**（PLAYBOOK §3 的「16 种」是陈旧数字，已在文档里注明） | **0** |
| `check_tool_groups.py --check-completeness` | `176 = 66 + 105 + 5`、`171 + 5 = …`、`missing=0 foreign=0`、`BYTES ADDED 8072` | **0** |
| `check_tool_groups.py --added` | 5 个新增工具、`SHA256 0295cf86…`、manifest ↔ 契约双向相等 | **0** |
| `check_tool_groups.py --generator-version` | 三方一致 `1.20.0` | **0** |
| `check_engine_anchor.ps1`（plain `ff796dbf9`、mono `ff796dbf9`、double `9c12c2383` 对 HEAD `b6fbb917b`） | 三个全部 **`ANCHOR_STRUCTURAL_EQUIVALENT` + `RESULT PASS`**；plain/mono `DIFF_COUNT=64 SAFE=64 RED=0`、double `34/34/0`；三个 `--version` 自报串分别为 `4.8.dev.custom_build.ff796dbf9` / `4.8.dev.mono.custom_build.ff796dbf9` / `4.8.dev.double.custom_build.9c12c2383` | **0 ×3** |

**自洽性结论**：文档里的机器数字 = 我当场跑出来的数字，没有一处「转述别人报告的数字而未经核对」被写成
「我实测」——凡属**引用**（如门①的 3/3、门②的 14/14、门③/④的 345/1771、门⑤的 23/23 ×2、门⑥ 的 101/101 探针、
双精度的 345/345）都明确标了**采集锚点**（`9c12c2383` / `ff796dbf9` / `4512d14c7e` / `e45ad638e6`）与证据路径。

## B.4 deviations / blockers / next step

### B.4.1 deviations（逐条显式）

1. **`--coverage` 的拼写数在文档之间不一致（现状记录，非本批引入）**：脚本在 `[sha:b6fbb917b]` 上打印
   **17 种**，而 `PLAYBOOK-group-port.md` §3 的正文写「16 种已声明拼写」。文档里两个数字都写了，
   以**脚本 `--coverage` 的输出为准**（PLAYBOOK 是决策者维护，B 角色不改）。
2. **本文档对「六条纪律」的演示脚本，凡仓库内没有对应演示脚本的，只用检查器的 `--probes` 模式**：
   恒真断言与退出传播两条例的**真实缺陷演示**分别落在 `mcp059_d2_failure_demo.ps1` 与
   `mcp069_exit_propagation_demo.ps1`；假等待的**五情景反例**在 `evidence/task061/`。
   **没有**为凑齐「每条一个脚本」而虚构路径。
3. **B 部分没有重跑门**：任务书 §B 是**文档**交付；重跑门会启动引擎/占用 9888/9889（并且门③′ 会触发一次
   15 min 级构建），与「只写文档」的角色边界冲突。因此文档里的门数字**全部带采集锚点**，并另附
   §B.3 的只读实跑表作为「本次现场」的部分。
4. **`REPORT-AUDIT-ENGINE.md` 的正文写「五条纪律」，本文件写「六条」**：第六条（锚点不得假红）是
   TASK-072 新增的，其审计报告是 `REPORT-072`。文档里两条来源都标了，不把 072 的结论回填成 069 的。

### B.4.2 blockers

**无。** 没有需要用户协助的环境/网络/权限问题。

### B.4.3 next_step（给决策者）

1. **落笔 `DESIGN-DETAIL` 的门③ 口径**（§16 第 3 条 + 可选 GDR-29），建议文本见本报告 A 部分 §6。
2. **是否把双精度开关也接到 `mcp057_gates.ps1`**（3 行 + 一次重跑）。
3. **`PLAYBOOK §3` 的「16 种拼写」订正为脚本实际打印的 17 种**（决策者维护的文件）。
4. **§5.4 的四个小债务**（`check_hardcoded_counts.py` 2 行 UNCLASSIFIED、三类 PINNED 改派生、
   `.godot` 收窄立项、mono 锚点漂移）各可单开一个小批次。
