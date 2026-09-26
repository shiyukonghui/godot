# REPORT-072 — 修「锚点假红」：`engines_match_head` 升级为**结构性等价证明**

- **任务书**：`modules/mcp_server/docs/tasks/TASK-072-anchor-structural-equivalence.md`
- **来源**：`REPORT-071-guard-inventory-and-test-config.md` §门⑤（唯一非零 = `mcp052`/`mcp053` 的 `engines_match_head`）
- **裁决**：D130（用户）
- **契约**：**176**（条数不变；门① 实况 `contract=176`，编辑器 **153** / 游戏 **72**，并集 **176**）
- **构建锚点（D86 ①）**：`ff796dbf9` —— 两个二进制自报 `4.8.dev.custom_build.ff796dbf9` /
  `4.8.dev.mono.custom_build.ff796dbf9`，与 `git rev-parse --short=9 HEAD` **逐字一致**。门①–⑥ 与回归电池全部在该锚点上采集。
- **交付提交**：见 §9。**未 push**。
- **9877**：全程未占用、未杀、未重启（门① `pid_before=-1 pid_after=-1`；门② `G230 asked_by_us=False`）。

---

## 0. 一句话结论

判据从「二进制自报版本 **等于** HEAD 短 sha」升级为「自报锚点 `A` 是 HEAD `H` 的**祖先**，且 `git diff --name-only A..H`
里**没有编译输入**」。四种结论机器可读；`config.py`/`SCsub`/未知后缀一律判红（fail-closed）。判据只存在于**一个脚本**
`scripts/check_engine_anchor.ps1`，`mcp052`/`mcp053` 及其它做锚点检查的脚本**只调用它**。
真实仓库 + 真实二进制的反例演示证明：只改 `.md` → **不红**；改 `.cpp` → **红**；非祖先 → **红**；真重建 → **`ANCHOR_EQUAL`**。

**回归电池（`mcp056_regression_battery.ps1`，15 步）现在 `ALL REGRESSION STEPS EXIT 0`，exit 0** —— REPORT-071 的
`FAILED STEPS: 2` 消失，`mcp052` **53/53**、`mcp053` **73/73**，且**没有第二类失败**。

---

## 1. 判据（唯一事实源：`scripts/check_engine_anchor.ps1`）

设 `A` = 二进制 `--version` 自报锚点（`4.8.dev[.mono].custom_build.<sha>` 尾部的十六进制 token，`[0-9a-f]{7,40}`），
`H` = HEAD（`git rev-parse --short=9 HEAD`，或调用者显式给出）。

| 结论 | 条件 | 门 |
|---|---|---|
| `ANCHOR_EQUAL` | `A`、`H` 解析到**同一个 commit** | **PASS** |
| `ANCHOR_STRUCTURAL_EQUIVALENT` | `A` 是 `H` 的**祖先**，且 `git diff --name-only --no-renames A..H` **全部**落在非编译白名单内；**打印安全差异清单 + 计数** | **PASS** |
| `ANCHOR_STALE_COMPILED` | `A` 是 `H` 的祖先，但差异里**至少一个编译输入**；**打印导致红的清单（`KIND:path`）** | **FAIL** |
| `ANCHOR_NOT_ANCESTOR` | `A` 解析不到 commit，或不在 `H` 的历史里（切分支 / rebase / 假锚点）；**没有十六进制 token** 也走这条 | **FAIL** |

**fail-closed 的分类（`--no-renames`，重命名藏不住编译输入）**

- **红（编译输入）**：`.cpp .cxx .cc .c .h .hpp .hh .hxx .inl .inc .cs .tscn .tres .gd .godot .build .csproj .sln .vcxproj
  .asm .s .m .mm .rc .def .java .kt .swift .rs .go`；无扩展名的 `SConstruct / SConscript / SCsub / Makefile / GnuMakefile`。
- **`config.py` 被显式从 `.py` 白名单里挖出来判红**：`modules/*/config.py` 是 SCons 编译输入，把它当「脚本」放行就是闭包上的洞。
  这是**加强**，不是放宽（任务书 §2.1 的白名单是下限，不是上限）。
- **安全**：`.md .json .txt .ps1 .py .cmd .sh .bat .psm1 .psd1 .yml .yaml .toml .cfg .ini .csv .rst .adoc .html .css
  .svg .png .jpg .jpeg .webp .gif .log` 与 `.gitignore .gitattributes .gitmodules .editorconfig LICENSE COPYING AUTHORS NOTICE`。
- **未列出的后缀 = `UNCLASSIFIED` = 红**（探针 A5 实测）。

**不削弱（任务书 §2.2）**：任何 `ANCHOR_STRUCTURAL_EQUIVALENT` 的输出里**没有**「等于 HEAD」这种说法。每条 verdict 的
`Summary` 同时带 **二进制自报锚点 + `anchor_reported` + HEAD + 判据原文 + 完整差异清单 + 计数 + 理由**，逐字例如：

```
anchor=e0534f5b5 anchor_reported=e0534f5b5 head=82ffdfc7c... verdict=ANCHOR_STRUCTURAL_EQUIVALENT ancestor=yes
diff_count=1 safe_count=1 red_count=0 criterion="A is an ancestor of H (A == H counts) and git diff --name-only A..H
contains no compile input (safe = declared non-compiling whitelist, everything else red)"
reason="... the binary is NOT equal to HEAD, it is structurally equivalent to it"
diff=[S:modules/mcp_server/docs/tasks/PLAYBOOK-group-port.md]
```

**一个「未知即红」的边界，明确写下来**：本判据是**拼写可见**的（与门⑥ 同类）。`git diff` 只回答「这些提交碰了哪些路径」，
所以它**不知道**某个 `.json` 会不会被某个 Python 生成器读成编译输入；白名单之外一律红是与门⑥ 同样的**有界保证**。

### 1.1 同批实测并修掉的一个真实缺陷（append-only 记录）

第一版 `check_engine_anchor.ps1` 带 `param([string]$RepoRoot = '', ...)` 块。**被 dot-source 的脚本，其 `param()` 会把
参数绑定进调用者作用域** —— 于是 `mcp052` 在 dot-source 之后 `$RepoRoot` 被静默清空成 `''`（同一批的探针第一次运行
打印 `repo under test :`（空）并把每条 git 命令指向错误的仓库，实测到）。修法：该文件**没有 `param()`**，
命令模式从 `$args` 解析，库模式只定义函数，**不触碰调用者的任何变量**。这条写进文件头部注释，因为它是一个会静默
改变调用者语义的坑。

## 2. 落地：没有第二份判据

| 文件 | sha256 | 角色 |
|---|---|---|
| `scripts/check_engine_anchor.ps1` | `94cd937aace88a00e63415f34b919b6c091aada8bd31ae3f17d633370417613e` | **唯一判据**；库模式（dot-source + `Get-McpEngineAnchorVerdict`）+ 命令模式（`-VersionText`/`-Anchor`/`-HeadSha`/`-RepoRoot`/`-Json`，exit 0/1/3） |
| `scripts/mcp072_anchor_judge_probe.ps1` | `aa282ba017250cae13fbaad0c7dc42f5b6a1da15add71fe7d01b6b8bc94874e3` | 判据探针（决策表 + 分类表 + 真实二进制）：**13/13 PASS，exit 0** |
| `scripts/mcp072_anchor_counterexample_probe.ps1` | `44d800f0530e4b718e861fa3907198d7d200f334be21681d191dd241d48e1e2e` | 能力保留反例（真实仓库、临时提交、`finally` 里 `reset --hard`）：**10/10 PASS，exit 0** |

调用它的脚本（全部 dot-source + `Get-McpEngineAnchorVerdict`，**没有一处复制判据**）：

`mcp016_hoist_equivalence.ps1`、`mcp024b_ergonomics_batch2_evidence.ps1`、`mcp025_e3_writeside_evidence.ps1`、
`mcp026_e9_e6_evidence.ps1`、`mcp047_m3_mono_check.ps1`、**`mcp052_added_tools_evidence.ps1`**、
**`mcp053_added_tools_evidence.ps1`**、`mcp057_gates.ps1`、`mcp057_settings_publish_evidence.ps1`、`mcp059_gates.ps1`、
`mcp059_section_switch_evidence.ps1`、`mcp063_product_defects_evidence.ps1`、`mcp070_double_precision_evidence.ps1`、
`mcp070_mono_csharp_evidence.ps1`、`mcp070_windowed_preserve_evidence.ps1`（**15 个脚本** + 2 个探针）。

- **check id 与检查条数不变**：`mcp052` 仍是 53 条、`mcp053` 仍是 73 条，`engines_match_head` 这个 id 保留（连续性），
  变的只有判据与证据行内容。**没有新增检查、没有删除检查。**
- **`mcp016` 的特殊性（显式声明）**：它 `checkout PRE` → 重建 → `checkout AFTER` → 重建，下一步是**逐字节**比较响应；
  它要的是「二进制 == **我刚构建的那棵树的 revision**」，**不是**「锚点 vs HEAD」。因此它调用同一个判据，但把比较目标
  设为**被 check out 的 revision**，并且**只接受 `ANCHOR_EQUAL`**（旧的子串判断 → 现在精确解析 commit）。
  这是判据的统一，不是放宽；若改成「结构等价」会让逐字节比较失去意义。
- **未改动的脚本**：只**记录** `git HEAD`、不判红的脚本（`mcp018`/`mcp019`/`mcp020`/`mcp021`/`mcp028`/`mcp042_port_guard_probes`…）
  保持原样 —— 它们的 `git HEAD` 是记录，不是锚点检查。`mcp055`/`mcp057`/`mcp059` 里对 `--short` 的**打印**也已改为调用判据。

## 3. 反例演示（**最关键**，任务书 §2.3）

`mcp072_anchor_counterexample_probe.ps1` 在**真实仓库**上用**临时提交**构造 4 种情形，`finally` 里 `git reset --hard`
还原，并断言 HEAD、`porcelain -uno`、两个被改文件的 sha256 **逐字节回到起点**（重新运行后实测：`S0 ... porcelain_clean=True
docs_sha_unchanged=True cpp_sha_unchanged=True`）。完整输出：`docs/reports/evidence/task072/counterexample_probe.txt`
（sha256 `082efb9bc8164a286c0ea20f3916fd6afa86f06fcc2ae4af5c5501c8dbef45a2`），START `2026-09-25 10:44:49 UTC` /
`18:44:49` 本地，END `10:44:56 UTC`，耗时 **7.1 s**。

| # | 情形 | 判据实测 | 结果 |
|---|---|---|---|
| ④ | 真重建 mono/plain 到 HEAD（`e0534f5b5`），`--version='4.8.dev[.mono].custom_build.e0534f5b5'` | `ANCHOR_EQUAL`（`diff_count=0`） | **PASS** |
| ① | 只改一个 `.md`（`docs/tasks/PLAYBOOK-group-port.md`）后**不重建**，HEAD 前进一个临时提交 | `ANCHOR_STRUCTURAL_EQUIVALENT`，`safe_count=1`，`red_count=0`，`diff=[S:...PLAYBOOK-group-port.md]` | **PASS（不红）** |
| ② | 改一个 `.cpp`（`tools/registration.cpp`）后**不重建** | `ANCHOR_STALE_COMPILED`，`red_count=1`，`diff=[R:modules/mcp_server/tools/registration.cpp(COMPILE_INPUT)]` | **FAIL（红）** |
| ③a | 锚点 = 一个**真实存在但不在 HEAD 历史里**的 commit（`reset --hard` 之后仍可解析） | `ANCHOR_NOT_ANCESTOR`，`ancestor=no` | **FAIL（红）** |
| ③b | 锚点 = `4.8.dev.custom_build.deadbeefc`（伪造） | `ANCHOR_NOT_ANCESTOR`，`reason="the reported anchor 'deadbeefc' does not resolve to a commit"` | **FAIL（红）** |
| 1b | 同一判据的**命令行入口**（`-File check_engine_anchor.ps1 -VersionText ... -HeadSha ...`）在同一情形下 | `ANCHOR_JUDGE VERDICT=ANCHOR_STRUCTURAL_EQUIVALENT` / `RESULT PASS`，exit 0 | **PASS** |

> ①②③ 的红/绿相位输出**当场保存**在同一次运行的文件里（`counterexample_probe.txt`），没有事后重排版。

## 4. 判据自身的探针（`mcp072_anchor_judge_probe.ps1`，13/13 PASS，exit 0）

- **A1–A10 决策表**：在 `%TEMP%\mcp072\anchor-synthetic` 的**一次性 git 仓库**上建 6 个提交 + 1 个侧分支，逐条断言
  `EQUAL` / `docs-only → STRUCTURAL` / `cpp → STALE` / `config.py → STALE` / `未分类后缀 → STALE` / `.gitignore → STRUCTURAL` /
  `侧分支 → NOT_ANCESTOR` / `不可解析 sha → NOT_ANCESTOR` / `无 token 的 --version → NOT_ANCESTOR` / `从 --version 行里抽 token`。
- **B1 分类表**：26 行字面表（含 `SConstruct`/`SConscript`/`SCsub`/`config.py`/`.gitignore`/`UNCLASSIFIED`），`mismatches=0`。
- **C**：真实两个二进制的 verdict 记录（不作 PASS/FAIL 断言，只钉住「不是空判据」+ token 真被解析出来）。

## 5. 门与纪律（全部在锚点 `ff796dbf9` 上）

| 门 | 命令 | 结果 | 退出码 |
|---|---|---|---|
| ① 契约子集逐字 | `scripts\check_contract_subset.ps1` | **3/3 PASS**；`contract=176`；`implemented_union = 153 (editor) / 72 (game)`；`guard_user_port_9877 pid_before=-1 pid_after=-1` | **0** |
| ② 三类证据（活） | `scripts\mcp071_gate2_live_evidence.ps1` | **14/14 PASS**；编辑器 `tools/list` 153（bytes 61863 sha256 `333b4a6858aa…`）、游戏 72（bytes 32973 sha256 `0ed732aff616…`）、并集 176 = 契约 176；成功 `project_get_info` / 缺参 `-32602` / 底层失败 `-32001 + data.suggestion`；跨工具链 `project_create_script → project_read_script → project_validate_script`；`G230 asked_by_us=False`；`porcelain -uall` 前后 sha256 相同 | **0** |
| ③ 模块 doctest（单精度） | `--headless --test --test-case="[MCPServer]*"` | **345 / 345 passed / 0 failed / 1429 skipped**；**23971 / 23971 assertions** | **0** |
| ④ 全引擎回归 | `--headless --test` | **1771 / 1771 passed / 0 failed / 3 skipped**；**448218 / 448218 assertions** | **0** |
| ⑤ `accept_m1` ×2 + 清单一致 | `mcp056_regression_battery.ps1`（步骤 1/2 + 比较） | 两次都 **23/23**；`accept_m1_pass_lists_agree\|0\|differing_lines=0` | **0** |
| ⑥ 收窄点清单（三段式） | ① `python scripts\check_narrowing_points.py`<br>② `... --coverage`<br>③ `scripts\mcp031_gate6_coverage_probes.ps1` | 三段全 **exit 0**；③ **101/101 checks passed**（含 `B1b_restored_scanned_75`、`B1b_restored_byte_identical`、`B1b_worktree_clean_of_probes`），探针后逐字节还原 | **0 / 0 / 0** |
| 生成器三连 | `check_tool_groups.py --check-completeness / --added / --generator-version` | 三个全 PASS（`BYTES ADDED 8072`、`SHA256 ADDED 0295cf86…`、`GENERATOR-VERSION 1.20.0`）；**契约条数 176 不变** | **0 / 0 / 0** |
| 退出码传播 | `python scripts\check_exit_propagation.py` | **PASS**（`every aggregator shape is guarded or pinned`） | **0** |

- **门③ 是单精度门**（跑 `bin\godot.windows.editor.x86_64.console.exe`）；`345 / 23971` 与 REPORT-071 基线**逐字一致**，未减少。
- **门⑥ 三段式 + §22.3b 规则 4**：本批 `tools/**` **零改动**，因此没有新增收窄点；门⑥ 只是回归确认。按 §22.3b 规则 4，
  这里**不**把门⑥ 变绿当成唯一证据 —— 本批改动全部在 `scripts/**`，与被扫描的收窄点集合不相交。
- **`check_exit_propagation.py` 的一个真实红相位（当场修掉）**：两个新探针最初把失败计数写成 `$script:Fails`，
  扫描器**声明的**守卫拼写是 `if ($script:Failures -gt 0)`，于是判 `UNDISCHARGED ... ps_check_printer`，exit 1。
  按「声明集合」的纪律改名为 `$script:Failures`（**没有改扫描器**），随后 **exit 0**。
  第一份红输出保存在 `check_exit_propagation.txt` 的最后修订之前；修后文件为
  sha256 `130130e28a1f2543625c1ad88876cb1d09115a4d4dbf33908298105d8b6efbb0`（PASS）。

## 6. 构建窗口（严格串行，START/END 不重叠，从 cmd 启动，不抑制输出）

| 构建 | 命令 | START | END | exit | 自报版本 |
|---|---|---|---|---|---|
| plain @H1 `e0534f5b5` | `build_local.cmd -Force` | 18:41:46.30 | 18:42:37.88 | 0 | `4.8.dev.custom_build.e0534f5b5` |
| mono @H1 `e0534f5b5` | `mcp057_build_mono.cmd` | 18:42:44.23 | 18:44:38.25 | 0 | `4.8.dev.mono.custom_build.e0534f5b5` |
| plain @H2 `ff796dbf9` | `build_local.cmd -Force` | 18:49:37.00 | 18:51:29.77 | 0 | `4.8.dev.custom_build.ff796dbf9` |
| mono @H2 `ff796dbf9` | `mcp057_build_mono.cmd` | 18:51:40.61 | 18:53:32.10 | 0 | `4.8.dev.mono.custom_build.ff796dbf9` |

- 四段窗口**互不重叠**，全程**只有一个 scons**（D62）；日志：`%TEMP%\mcp072\build_plain.log`、`build_mono.log`、
  `build_plain_h2.log`、`build_mono_h2.log`（START/END/EXIT_CODE 逐字在文件里）。
- `bin\godot.windows.editor.x86_64.console.exe` sha256 `4b269370db8ac449f1246657cf1daa331ec61d95c81f18ee468db08acd371331`
- `bin\godot.windows.editor.x86_64.mono.console.exe` sha256 `225198b3dd18de00107a206bb1fab0f2c126a663b86fdbee27de661e05c4bce9`
- **为什么 build 了两次**：H1 = 实现提交；H2 = 探针里失败计数改名（`check_exit_propagation.py` 的红相位）。
  H1→H2 **只动两个 `.ps1`**（无编译输入），所以第二次重建严格来说只为让 `--version == HEAD` 成立；
  这正是本任务要消灭的那类「必须记得重建」的负担 —— **本批之后不再需要**（见 §6.1）。

### 6.1 「重建窗口」的必要性**已经只在本批内**成立一次

H2 之后本批还提交了**报告与证据**（纯 `docs/**`）。按新判据，那两个提交之后二进制**不需要重建**：
`A = ff796dbf9` 是 `H` 的祖先，差异全是 `.md`/`.txt`/`.log` → `ANCHOR_STRUCTURAL_EQUIVALENT`（**PASS**）。
§8 给了这条的**端到端实测**（在报告提交之后直接跑 `mcp052`/`mcp053`）。

## 7. 回归电池：`ALL REGRESSION STEPS EXIT 0`（对照 REPORT-071 的 `FAILED STEPS: 2`）

`powershell -File mcp056_regression_battery.ps1 -EvidenceDir <repo>\docs\reports\evidence\task072\battery`，
**整脚本 exit 0**，`git HEAD: ff796dbf99facc7c6bc49b1b4ae42a0e6313506d`。
证据：`battery\summary.txt`（sha256 `0798f65f239490a641fab3a66665924fb6d14db2ca775c73d3a4daf3547a17f5`）、
`battery\restore_manifest.txt`（`504157bd0ee08051f4391a459c56d7349105957fcaa2f7e38debaeb38c99467d`）、
逐步 `.log`。

| # | 步骤 | exit | 归因 |
|---|---|---|---|
| 1–2 | `accept_m1_run1/2` | 0 / 0 | 两次都 **23/23**，`implemented tools = 153/72`，`contract = 176` |
| — | `accept_m1_pass_lists_agree` | **0** | `differing_lines=0`（门⑤ 判据） |
| 3–5 | `mcp041_gates` / `mcp042_gates` / `mcp043_gates` | 0 / 0 / 0 | `ALL STEPS EXIT 0`（17 / 19 / 29 步）。它们打印的 `tree dirty after the run:` 是**记录**不是判据（REPORT-070 §4.2 已判定），本批的脏树只有 4 个既有未跟踪物 + 本批证据目录 |
| 6–11 | `mcp010` / `mcp019` / `mcp027` / `mcp044` / `mcp045` / `mcp046` | 0 ×6 | 29/29、H1 9877 guard PASS、60/60、40/40、15/15、23/23 |
| 12–13 | `mcp050` / `mcp051` | 0 / 0 | 9877 guard `pass=True`；`task050/red/summary.json` sha256 `ecab8cbc…`、`task051/red/summary.json` sha256 `75715dec…` |
| **14** | **`mcp052_added_tools_evidence`** | **0**（TASK-071 时是 **1**） | **`53/53 checks passed`**。唯一失败检查 `engines_match_head` 现在 **PASS** |
| **15** | **`mcp053_added_tools_evidence`** | **0**（TASK-071 时是 **1**） | **`73/73 checks passed`**。同上 |
| — | `tracked_evidence_restored` | **0** | `declared leftovers=0 (every declared artifact is back); undeclared paths left alone=5; restore failures=0; git diff --stat after=0 line(s)` |

**§门⑤ 的对象逐字证据**（`battery\mcp052_added_tools_evidence.log` / `mcp053_added_tools_evidence.log`，
UTF-16LE，battery 自己的 `*>` 写法）：

```
[PASS] engines_match_head
       plain --version='4.8.dev.custom_build.ff796dbf9' | anchor=ff796dbf9 anchor_reported=ff796dbf9 head=ff796dbf9
       verdict=ANCHOR_EQUAL ancestor=yes diff_count=0 safe_count=0 red_count=0 criterion="A is an ancestor of H
       (A == H counts) and git diff --name-only A..H contains no compile input (safe = declared non-compiling whitelist,
       everything else red)" reason="the binary self-reports the very commit HEAD points at; the diff is empty by
       construction" diff=[<empty>] || mono --version='4.8.dev.mono.custom_build.ff796dbf9' | ... verdict=ANCHOR_EQUAL ...
[PASS] mono_engine_is_the_mono_build
```

**还原清单现场**：`RESTORED` **56** 条已跟踪证据（task050/051/053 三根下逐字节回 HEAD）+ `RESTORED-NEW` 1 条
（`task051/red/e20_child_status.json`）+ `SUMMARY restored=56 removed=1 kept-dirty-before=0 untouched=4
missing-untracked=0 changed-untracked=0 appeared-untracked=5 pruned-dirs=0`。被 `UNTOUCHED` 的 5 条全部是
**未声明**的本批证据/报告（battery 自己的 3 个聚合文件 + `restore_manifest.txt` + 本报告）——TASK-069
「按声明还原、声明外只报告不动」的现场复现。

## 8. 端到端：报告提交之后**不重建**，`mcp052`/`mcp053` 仍然绿

### 8.1 实测（`1cd640840`，二进制仍是 `ff796dbf9`，**没有重建**）

报告与证据提交成 `1cd640840`（**纯 `docs/**`**），HEAD 前进而二进制留在 `ff796dbf9`。这正是 TASK-071 出现假红的
那个情形；本批直接跑两个门脚本：

| 脚本 | `engines_match_head` | verdict | 差异 | 结果 | exit |
|---|---|---|---|---|---|
| `mcp052_added_tools_evidence.ps1` | **PASS** | `ANCHOR_STRUCTURAL_EQUIVALENT` | `diff_count=23 safe_count=23 red_count=0` | **53/53 checks passed** | **0** |
| `mcp053_added_tools_evidence.ps1` | **PASS** | `ANCHOR_STRUCTURAL_EQUIVALENT` | `diff_count=23 safe_count=23 red_count=0` | **73/73 checks passed** | **0** |

- START/END：`mcp052` `19:29:50.55` → exit 0；`mcp053` `19:30:29.09` → exit 0。
- 证据（**不是「等于 HEAD」的说法**，逐字保留锚点 + HEAD + 判据 + 差异清单）：
  `evidence/task072/structural_mcp052.txt`、`structural_mcp053.txt`，逐字如：
  `anchor=ff796dbf9 anchor_reported=ff796dbf9 head=1cd640840 verdict=ANCHOR_STRUCTURAL_EQUIVALENT ancestor=yes
  diff_count=23 safe_count=23 red_count=0 ... reason="ff796dbf9 is an ancestor of 1cd640840 and all 23 file(s) in the
  diff are non-compiling; the binary is NOT equal to HEAD, it is structurally equivalent to it" diff=[S:...REPORT-072... S:...]`
- 两个脚本写脏的已跟踪证据（`docs/reports/evidence/task050|051|053`）在运行后已 `git checkout --` 还原，
  `porcelain -uno` 运行前后都是**空**，HEAD 前后都是 `1cd640840`。

> **这就是本任务要买的东西**：从今以后，只改文档/脚本的提交**不再要求重建 mono**才能让这两个门变绿；
> 而「二进制真的落后于一个编译输入」仍然由 §3 的 ①② 判红。

## 9. 提交

| sha | 一行说明 |
|---|---|
| `e0534f5b59` | `fix(mcp_server): TASK-072 one structural anchor judge for every anchor check (docs-only commits stop faking a stale binary)` —— 新建 `check_engine_anchor.ps1` + 2 个探针，改造 15 个做锚点检查的脚本，提交任务书 |
| `ff796dbf9` | `fix(mcp_server): TASK-072 probes name their failure counter the declared way (check_exit_propagation.py exit 0)` |
| `1cd6408403` | `docs(mcp_server): TASK-072 report and evidence - the structural anchor judge, its counter-examples and the green regression battery` |
| `37cc835898` | `docs(mcp_server): TASK-072 report - the end-to-end demonstration at a docs-only commit (mcp052 53/53, mcp053 73/73, no rebuild)` |

只有 `modules/mcp_server/**` 被修改（`scripts/**` 18 个文件、`docs/**` 报告与证据），**hof-rs 未写**，
`DESIGN-DETAIL` **未改**，**未 push**。

> **锚点与交付提交相差 N 个 `docs-only` 提交（与前几批同形，见 REPORT-071 §D.1.6）**：门与电池在 `ff796dbf9`
> 上采集（那时 `--version == HEAD` 逐字成立），其后是 2 个 `docs/**` 提交。**在本批之前**这会让下一次跑门假红；
> **在本批之后**它是 `ANCHOR_STRUCTURAL_EQUIVALENT` —— §8.1 逐字实测了这件事。本报告的最后一处回填也是一个
> `docs-only` 提交，因此 `git rev-parse --short=9 HEAD` 永远比本文件写下的 sha 新一截；这不是漂移，是判据的**正常工作**。

## 10. 证据清单（绝对路径均在 `code\godot\modules\mcp_server\docs\reports\evidence\task072\`，sha256 为提交前实测）

| 文件 | bytes | sha256 |
|---|---|---|
| `judge_probe.txt` | 9071 | `5b7b577dabd1df4f7441ba5a45bbe4443bd527ad1a253d7c16c4bdfd2540970f` |
| `counterexample_probe.txt` | 8213 | `082efb9bc8164a286c0ea20f3916fd6afa86f06fcc2ae4af5c5501c8dbef45a2` |
| `gate1_contract_subset.txt` | 15572 | `c53ce07348a87d2adbf9e6646467e702947eadf6a1d74e74a066a500d45c00c6` |
| `gate2_live_evidence.txt` | 5052 | `e00dbcfb734cc2fa69af3720788953c7fee403092988fa4ddda0efc2f7d1d5ff` |
| `gate3_module_doctest.txt` | 50522 | `93f20731ff8f4ca1ebd42958c743f44772647e353ed0d3a06c97996b605ee93d` |
| `gate4_full_engine.txt` | 15798 | `48e7e6cd85403554485da0cc1626a366818fd5f9c2f164b7173d770c2493ba90` |
| `gate6a_narrowing.txt` | 13520 | `c366c7b4616085f787d82e0c01590a302657da0199387f76bb6438812d694ebb` |
| `gate6b_coverage.txt` | 3433 | `9573a6fdeb99b614002d2670482fca7e678ad6cf5bacb1109e9393d0e61650cb` |
| `gate6c_probes.txt` | 31349 | `b55fe9caad3c07b4fedc2d310dffda1e78c303e0b2959b94137576da9553c905` |
| `toolgroups_completeness.txt` | 1621 | `85ec3ef503a1cafca859e5fa6190704e594aa21e20a8ea07eace60eaa924941e` |
| `toolgroups_added.txt` | 1774 | `349381533586f3cca6d290db5bcf97299087338e224cea9aed298ad06b17a8c1` |
| `toolgroups_generator.txt` | 416 | `0e70e6ca991a8da8d8aad8dfd3d0afa3d408b776440e71d14f65a9f9a117510e` |
| `check_exit_propagation.txt` | 982 | `130130e28a1f2543625c1ad88876cb1d09115a4d4dbf33908298105d8b6efbb0` |
| `battery/summary.txt` | 3848 | `0798f65f239490a641fab3a66665924fb6d14db2ca775c73d3a4daf3547a17f5` |
| `battery/restore_manifest.txt` | 6663 | `504157bd0ee08051f4391a459c56d7349105957fcaa2f7e38debaeb38c99467d` |
| `battery/accept_m1_pass_list_compare.txt` | 69 | `bc0828e4eb89b38c6717e42e5d7e191f7a2fe6e68af950a060fffa486b6f2037` |
| `battery/mcp052_added_tools_evidence.log` | 41296 | `ec8eaf845280e84709f9e201b16163d96cca89edb373d44a22618bcd4e21d824` |
| `battery/mcp053_added_tools_evidence.log` | 65744 | `f84403be11119ada0b9acb437d6473c527dfc1fbafd6aa26b98580842ca379a2` |
| `structural_mcp052.txt`（§8.1，`1cd640840` 上不重建跑门） | 24366 | `0ca93793d809378140aabf7820065aeee29d2ec4563ad156ca0c1a305758fb57` |
| `structural_mcp053.txt`（§8.1） | 36421 | `0d28eb30ef52b2cdb26be19dcc436651727afd0abe207983c5d5241d7c429411` |

- 二进制：plain `4b269370db8ac449f1246657cf1daa331ec61d95c81f18ee468db08acd371331`、
  mono `225198b3dd18de00107a206bb1fab0f2c126a663b86fdbee27de661e05c4bce9`（各 300544 bytes）。
- 判据与探针：`check_engine_anchor.ps1` `94cd937a…`、`mcp072_anchor_judge_probe.ps1` `aa282ba017250cae13fbaad0c7dc42f5b6a1da15add71fe7d01b6b8bc94874e3`、
  `mcp072_anchor_counterexample_probe.ps1` `44d800f0530e4b718e861fa3907198d7d200f334be21681d191dd241d48e1e2e`。
- 构建日志：`%TEMP%\mcp072\build_plain.log` / `build_mono.log` / `build_plain_h2.log` / `build_mono_h2.log`（在 `%TEMP%`，非仓库内）。
- **battery 的逐步 `.log` 是 UTF-16（battery 自己的 `*>` 写法），且被 `.gitignore` 的 `*.log` 覆盖**：
  按 TASK-071 的先例，只把**门⑤ 的两个对象**（`mcp052`/`mcp053`）用 `git add -f` 强制入库，其余 13 个步骤日志留在盘上不入库。
  这是一处**偏离**（§11.1），显式记录。

## 11. deviations / 限制 / blockers / next step

### 11.1 deviations（逐条显式）

1. **转化范围超出 `mcp052`/`mcp053`**：任务书 §2.4 说「及其它做锚点检查的脚本统一调用」，因此另外 **13** 个脚本
   （`mcp016`/`mcp024b`/`mcp025`/`mcp026`/`mcp047`/`mcp057_gates`/`mcp057_settings`/`mcp059_gates`/`mcp059_section`/
   `mcp063`/`mcp070_double`/`mcp070_mono`/`mcp070_windowed`）的锚点断言也改为调用同一判据。
   后果（显式声明）：这些脚本在**历史报告**里记录过的 sha256 **因此变旧**；它们的**判据语义**只在
   「锚点 vs HEAD」这一处变宽（`mcp016` 反而**变严**：子串 → 精确 commit）。本批**只**对
   `mcp052`/`mcp053`（门⑤ 对象，走完整 53/73）与全部四道门做了端到端重跑；另外 13 个脚本只做了
   **PowerShell AST 解析**（119 个脚本 `failures=0`）与单判断据的单元级探针，**没有**端到端重跑
   （它们各自会启动引擎、属于别的任务的证据）。
2. **两个 `.log` 用 `git add -f` 强制入库**（§10 末），因为 `.gitignore` 有 `*.log`。理由：`mcp052`/`mcp053` 的
   原始日志是门⑤ 的**逐字对象**，转码或摘录都会削弱证据。
3. **`config.py` 从 `.py` 白名单里挖出来判红**：任务书的白名单把 `*.py` 列为安全，我按「编译输入必须红」的
   上位要求做了**收窄例外**（**加强**闭包）。记录在此，因为它是一处与任务书字面的偏离。
4. **探针脚本的失败计数命名为 `$script:Failures`**：为让 `check_exit_propagation.py`（**声明集合**式检查）退出 0，
   按它声明的守卫拼写命名，而不是去改扫描器。这是「按声明改代码」而非「按代码改声明」。
5. **`mcp072_anchor_counterexample_probe.ps1` 只能在「二进制 == HEAD」时运行**（场景 ④ 断言 `ANCHOR_EQUAL`）。
   报告提交之后它按设计会以 exit 2 拒绝（工作树脏）或以 exit 1 失败（S4）。**这不是缺陷**，是场景 ④ 的定义；
   本批其证据取自 `ff796dbf9` 重建之后（§3）。
6. **报告与证据分两次提交**（`1cd640840` + §8.1 回填）。两次都是 `docs/**`，因此二进制不需要重建 ——
   这正是本任务的目的，`§8.1` 是它的实测。

### 11.2 已知限制（诚实声明，不夸大）

1. **判据是拼写可见的，不是证明**。它只看得见 `git diff` 给出的**路径**：一个「改了但 diff 认为无关」的
   编译输入、一个 `.json` 驱动的代码生成、一个白名单里的 `.py` 生成器（`config.py` 之外的），都在集合之外。
   与门⑥、`check_exit_propagation.py` 同类：**有界保证 + 插入式探针**，不是「已经证明没有洞」。
2. **`UNCLASSIFIED` 一律红**是保守选择：它会拒绝一些其实无害的新后缀（例如 `*.yml` 已在白名单，但
   `*.proto`、`*.editorconfig` 之外的怪后缀会被判红）。代价是**可能的新假红**，收益是**不可能的新假绿**；
   按「假红腐蚀信任」的任务前提，这里选**偏向红灯**（并把它写进文件头与报告，便于下一个人加白名单时知道要论证什么）。
3. **`ANCHOR_STRUCTURAL_EQUIVALENT` 仍然是一个「推断」而不是「已验证」**：它说的是「这些提交**不可能**改变编译结果」，
   而不是「二进制里就是这些源码」。因此证据行永远打印锚点与差异清单，**不**把结论压缩成「等于 HEAD」。
4. **探针 A1–A10 在一次性仓库里构造**（`%TEMP%`），场景 ①②③④ 在真实仓库上用**临时提交**构造（`finally` 里 `reset --hard`，
   实测 HEAD / porcelain / 两个文件 sha256 全部回位）。两者都不是「真实第三方误操作」的现场。

### 11.3 blockers

**无。**

### 11.4 next step（给决策者）

1. **门③ 是否加 `precision=double` 变体**：REPORT-071 §B.4 的建议仍然挂着，本批没碰（不在范围内）。
2. **是否把「锚点判据」写进规范**：`DESIGN-DETAIL` 由决策者维护。本批只在报告里给出判据与四条 verdict；
   如要进门规范，建议连同「未分类后缀一律红」的保守选择一起写入，并要求任何新增白名单条目附论证。
3. **`check_engine_anchor.ps1` 的继承者**：若将来出现「锚点不是 sha」的自报格式（例如带 `-dirty` 后缀），
   `Get-McpAnchorFromVersionText` 是唯一需要改的地方 —— diff 里**不应**再出现第二份判据。
4. **13 个历史脚本的 `sha256` 已在历史报告里变旧**（§11.1.1）：若决策者要求历史报告同步，那是**另一次**
   append-only 勘误批次，本批不代劳。

---

## 12. 纪律清单

| 要求 | 状态 |
|---|---|
| 只改 `modules/mcp_server/**`；hof-rs 只读 | ✅ 改动全在 `modules/mcp_server/{scripts,docs/tasks,docs/reports}`；hof-rs 未写 |
| 不改 `DESIGN-DETAIL`（要改先报） | ✅ 未改；判据只写在报告与脚本头 |
| 绝不占用/杀/重启 9877 | ✅ 门① `pid_before=-1 pid_after=-1`；门② `G230 asked_by_us=False`；电池 `pass=True classification=environment_fact_no_listener_before_or_after` |
| 端口 9888/9889 | ✅ 全程只用这两个 |
| 禁止 push | ✅ 未 push |
| 构建严格串行、从 cmd 启动、不抑制输出 | ✅ 四段窗口互不重叠；全部从 `.cmd` 启动；`MCP_BUILD_LOG` 落盘且控制台输出 |
| 证据 `curl.exe -s -o` + sha256 | ✅ 门② 的响应全部 `curl.exe -s -o` 落盘并给 sha256（`G203`–`G231` 逐条） |
| `.ps1` 纯 ASCII | ✅ 本批新增/修改的 **18** 个 `.ps1` 非 ASCII 字节数全为 **0** |
| 红相位输出当场保存 | ✅ `counterexample_probe.txt`（情形 ②③ 的红在同一文件里）；`check_exit_propagation.txt` 的 `UNDISCHARGED` 红相位在修前实测并记录（§门⑥ 段） |
| 门⑥ 三段式 + §22.3b 规则 4 | ✅ 三段全 exit 0（101/101 探针）；`tools/**` 零改动，故无新增收窄点，且**不**把门⑥ 变绿当唯一证据 |
| `--check-completeness/--added/--generator-version` exit 0 | ✅ 三个都 exit 0；契约 176 不变 |
| `accept_m1` ×2 清单一致 | ✅ `differing_lines=0`（各 23/23） |
| `check_exit_propagation.py` exit 0 | ✅ PASS |
| 回归逐条归因 | ✅ §7 表逐步骤列出 exit 与判据 |
| 结论按 D86 标锚点 | ✅ 全文结论标 `ff796dbf9`（构建/门）与 `1cd640840`（§8.1 结构性演示）；既有漂移标 `7b8478a7da` / `4512d14c7e` / `3cbaacd6bd` |
| 产物一律绝对路径 | ✅ 报告与证据均为绝对路径 |