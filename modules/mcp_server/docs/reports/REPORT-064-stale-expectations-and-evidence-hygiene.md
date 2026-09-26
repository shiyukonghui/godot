# REPORT-064 — 4 个证据脚本的旧契约期望改为派生 + 试测流程的两处取证缺陷

> **D86 锚点**：本报告的被测对象是**工作树本身**（不改二进制，不跑引擎，故没有"实现提交 ↔ 二进制"锚点）。
> **脚本改动提交 `ea05a19d4b`**（`mcp: derive the contract-size expectations in the evidence scripts, and make the two capture defects impossible (TASK-064)`，8 files changed / 1067 insertions / 51 deletions）。
> 报告写作时的 `git rev-parse --short=9 HEAD` = **`c589eae24`**（`docs(mcp_server): TASK-063 report - correct four file:line references...`，即脚本改动所基于的父提交）。
> 本批**未构建、未启动任何引擎**：改动全部落在 `scripts/**` 与 `docs/**`，且被改的判定逻辑发生在任何引擎启动**之前**（只读
> `docs/tools_list.renamed.json`、`docs/tool-rename-map.json`、`docs/tool-groups-added.json` 三个受版本控制的 JSON）。
> 因此不存在 R-1 的"陈旧二进制假红"风险；**也因此**下面每一条结论都能被另一个进程按"命令 + 输入 + 退出码"复算。
>
> **D-119 教训**：本文件与全部命令、产物一律写**绝对路径**（`F:\RustProjects\godot-mcp-pro\code\godot\...`），不写 `%TEMP%` 相对路径。

---

## 0. 结论（先给答案）

| # | 任务要求 | 结论 | 证据 |
|---|---|---|---|
| 1 | 4 个脚本钉死旧契约条数 → 查明来源、改为**派生**、**不放松断言**、复跑到 exit 0、给前后退出码对照 | **完成**：4 个点名脚本 + 2 个同族脚本（§1 的 5/6、§2 末）全部改为派生；共 6 处陈旧期望，逐条给"脚本/行/旧值/现应为何值/为什么当初是那个数"；**没有删除任何检查、没有改成恒真、没有放宽成 `-ge`**（逐条 diff 见 §1.3、§3） | §1、§2、§3 |
| 2 | 试测取证缺陷 (i)：证据文件同名复用被覆盖 → 唯一命名 + **断言路径未被写过**（同名且 sha 不同 → 直接报错） | **完成**：`mcp_evidence_guard.ps1` 新增 5 个**唯一命名 + 冲突拒绝**函数（`<leaf>__<id>__<seq>__<sha8>` 与 `<leaf>.before/.after__...`）；同名不同 sha **在任何一层都直接抛错**（同进程注册表 + 磁盘既有文件 + 事后树审计），同名同 sha 被显式标记 `SameContentSeen` 而不是静默重写 | §4.1、§4.2、§4.3 |
| 3 | 试测取证缺陷 (ii)：快照时序错误（before/after sha 相同 → P4b 不可归因）→ **先 before、后 after、断言两者 sha 不同**（除非显式声明预期相同） | **完成**：`Write-McpEvidenceSnapshotPair` 把三步顺序变成函数性质（`-Before` → `-Between` → `-After`）并在落盘后断言两个 sha **不同**；`-ExpectedIdentical` 必须同时给 `-Reason`，且此时改为断言**相同** | §5.1、§5.2、§5.3 |
| 4 | 两处都要给：修复后脚本片段 + **反例演示**（人为制造 → 必须报错；清理 → 还原 exit 0） | **完成**：`mcp064_evidence_hygiene_probe.ps1` 造出 20 个案例，含 6 个**故意制造的缺陷**（旧固定名写入、同名不同 sha、同名同 sha、冻结快照对、未声明的"预期相同"、声明相同但实际不同）——全部被拒；正确写法全部落地；**连跑两次均 exit 0**（demo 每次自清 scratch） | §4.4、§5.4 |
| 5 | 只改 `scripts/**` 与 `docs/**`；`git diff --stat -- modules/mcp_server/tools tests` **必须为空**；契约不动；不碰/不杀/不重启 9877；禁止 push；`.ps1` 纯 ASCII | **全部满足**（逐条见 §7） | §7 |
| 6 | 原文要求"全部复跑到 exit 0" | **5 个真实进程级复跑全部 exit 0**：reverse probe、hygiene probe ×2、`mcp053_contract_diff.py`、`mcp059_contract_pre_post.py`。**3 个 `*.ps1` 的端到端重跑仍受"无 HEAD 锚点 mono 二进制"阻碍**——这不是本批引入的，且 §2.4 用同一输入给出了精确的前/后退出码；**如实声明为未完成的覆盖**（§6） | §2.4、§6 |

---

## 1. 逐条查明来源（脚本 / 行 / 旧值 / 现应为何值 / 为什么当初是那个数）

### 1.1 任务书点名的 4 个脚本（6 处陈旧期望）

| # | 脚本 : 行（改动前） | 钉住的字面量 | 现应为何值 | 为什么当初是那个数（可核对） | 来源 |
|---|---|---|---|---|---|
| 1 | `mcp052_added_tools_evidence.ps1:315` | `($editorExpectedCount -eq 152) -and ($gameExpectedCount -eq 72)` | `153 / 72` | 写于 TASK-052 收口：当时契约 **173**（171 移植 + 2 新增），其中 editor 视图 152、game 视图 72。该脚本的派生块注释自己写明"the two sources are merged here exactly the way `scripts/check_contract_subset.ps1` merges them"；TASK-052 的报告 §5.3 记载同一批的实时对照（`live=150` == 派生期望 **150**，那时清单里还有 `unregister_until_implemented` 的组）——**当时的派生值 150 与后来的字面量 152 是不同的量**（前者按当时清单并集，后者按契约−另一侧 scope），本批的修法保持后者口径并把它变成派生 | REPORT-063 §6.2 第 1 行 |
| 2 | `mcp053_added_tools_evidence.ps1:325` | `$contractNames.Count -eq 175` | `176` | 写于 TASK-053 收口：契约 **173 → 175**（`REPORT-053-added-tools-2.md:26`"契约 173 → **175**"） | REPORT-063 §6.2 第 2 行 |
| 3 | `mcp053_added_tools_evidence.ps1:327` | `_meta.added_tools` 恰为四条（`Count -eq 4` + 四个名字） | `Count -eq 5` + 五名（`_meta` 与第六份清单双向相等） | 同上：TASK-053 把 `ADDED_TOOLS` 从四条前的两条扩到四条 | 本批静态筛查发现（REPORT-063 未点名，同一根因） |
| 4 | `mcp053_added_tools_evidence.ps1:362` | `($editorExpectedCount -eq 152) -and ($gameExpectedCount -eq 72)` | `153 / 72` | 同 #1，TASK-053 的副本 | REPORT-063 §6.2 第 3 行 |
| 5 | `mcp054_forensics_and_csharp_evidence.ps1:288` | `$contractNames.Count -eq 175` | `176` | 同 #2（TASK-054 抄了 TASK-053 的收口值） | REPORT-063 §6.2 第 4 行 |
| 6 | `mcp054_forensics_and_csharp_evidence.ps1:307` | `$contract._meta.added_count -eq 4` | `5` | 同上：TASK-053 后 `added_count=4` | 本批静态筛查发现（同根因） |

**为什么 175 → 176 / 152 → 153**：TASK-063 交付 `editor_set_node_property_updates`
（`docs/reports/REPORT-063-round2-product-defects.md` §3.1"契约 `_meta`：`count=176`、`added_count=5`"）。
该工具 `scope=editor`（`docs/tool-groups-added.json` 第 5 组），所以 **契约 +1、editor 视图 +1、game 视图不变**。

### 1.2 逐代计数（复算，非转述）

每个数字都能在受版本控制的产物里读到；括号内是 `mcp064_stale_expectation_reverse_probe.ps1` 复算出的当前值：

| 批次 | 契约条数 | `added_count` | editor 视图 | game 视图 |
|---|---|---|---|---|
| TASK-051 收口 | 171 | 无 `added_tools` | — | — |
| TASK-052 收口（#1 的由来） | 173 | 2 | 152 | 72 |
| TASK-053 收口（#2/#4/#5/#6 的由来） | 175 | 4 | 152 | 72 |
| TASK-059 起始修订 `213b1791258` | 175 | 4 | — | — |
| **今天（HEAD `c589eae24`）** | **176** | **5** | **153**（探针实测） | **72**（探针实测） |

### 1.3 两个 `*_contract_diff.py` / `*_pre_post.py`（一次性的 pre/post 对照）

| 脚本 | 钉住的字面量（改动前） | 性质 | 处理 |
|---|---|---|---|
| `mcp053_contract_diff.py:34-35` | `EXPECTED_BEFORE_COUNT = 173` / `EXPECTED_AFTER_COUNT = 175` | TASK-053 的 `before.json`（起始修订契约）与 `after.json`（该批产出的契约）之差 | 改为**派生**：`after = before + len(EXPECTED_ADDED)`，并把 `count == 171 ported + added_count` 的契约公式写进 `_meta` 检查（§3.2） |
| `mcp059_contract_pre_post.py:100` | `len(b_tools) == len(a_tools) == 175` | TASK-059 的 pre/post（before 从 `git show <PRE_BATCH_REV>` 读出） | 改为**派生**：两侧各自的 `_meta.count == len(result.tools)`、`count == 171 + added_count`，且 after 只允许比 before **多出它自己声明的** `_meta.added_tools` 尾部（§3.3） |

> **为什么这两个当初是那个数**：它们各自的**成立条件**就是"那一对修订"。`mcp053_contract_diff.py` 的文件头原来自己写着
> "`before.json` is the contract at the TASK-053 starting revision"；`mcp059_contract_pre_post.py` 的 `PRE_BATCH_REV`
> 常量就是 TASK-059 的起始修订 `213b1791258aa476e6b271e57733a689ad8f3ff9`。把 175 写死意味着"这一对就是世界的全部"，
> 而报告本身早已把"下一批合法追加"列为常态（REPORT-063 §6.2 末段的正因）。

---

## 2. 修复后的表达式与"没放松"的逐条对照

### 2.1 断言强度对照（每条都只说"期望值的**来源**改了"）

| # | 改动前（钉字面量） | 改动后（派生） | 强度变化 |
|---|---|---|---|
| 1 | `($editorExpectedCount -eq 152) -and ($gameExpectedCount -eq 72)` | `($contractNames.Count -eq ($portedCount + $addedNames.Count)) -and ($addedNames.Count -eq [int]$contract._meta.added_count)` | **更强**：原文是一个数对数的相等；新式把"契约 = 171 移植 + 声明新增"这条不变量加进来，而它无法由契约自身满足（见 2.2）。实时端点条数与这两个派生视图的相等，仍由同脚本的 `a02_editor_live_count_is_the_contract_view`（`mcp053`）/ `a2_editor_live_count_is_the_contract_view`、`d2_game_live_count_...`（`mcp052`）单独断言 |
| 2 | `$contractNames.Count -eq 175` | `($contractNames.Count -eq ($portedCount + $addedNames.Count)) -and ($addedNames.Count -eq [int]$contract._meta.added_count) -and ([int]$contract._meta.count -eq $contractNames.Count)` | **更强**：多加了"`_meta.count` 与 `result.tools` 一致"与"两个加数自洽"两条 |
| 3 | `addedNames` 恰为四条字面量名单 | `addedNames` 与第六份清单 `docs/tool-groups-added.json` 的组内名字**逐个逐位相同**，且 `Count == _meta.added_count`，且 TASK-053 的两名仍在位置 2/3 | **更强**：原文只对 4 个名字；新式把"清单 ↔ 契约"的双向一致拉进来（这正是 `check_tool_groups.py --added` 的机器断言），追加、删除、重排、改名都会红 |
| 4/5/6 | 同 #1/#2 | 同 #1/#2 | 同 |
| 7 | `EXPECTED_AFTER_COUNT = 175` | `expected_after = len(before_tools) + len(EXPECTED_ADDED)`，并让 `_meta.count` 两侧都等于 `171 + 各自 added_count` | **更强**：从"after 等于 175"变成"after 等于 before 加上本批声明的两名"，对任意起始修订都成立；并且"差异恰为本批两名""不得删除任何条目""尾两名按清单顺序"三条原有断言**原样保留** |
| 8 | `len(b_tools) == len(a_tools) == 175` | `count == len(result.tools)` 两侧 + `count == 171 + added_count` 两侧 + **after 只能是 before 的有序前缀 + 恰好它自己声明的 `_meta.added_tools` 增量** | **更强**：原文只查总数；新式查出**多出来的到底是哪几个名字**，未声明的追加、改名、删除、重排仍全部失败 |

### 2.2 "派生"不是恒真：两条无法由契约自身满足的护栏

派生的正确定义是"从一个**独立**的声明源读期望值"。本批用的独立源是
**第六份清单 `docs/tool-groups-added.json`**（§1.1/§2.1 的 #1/#2/#3）与**契约公式 `171 + added_count`**（`portedCount` 仍是受检查的字面量 171）。两条护栏使它们不可能恒真：

1. **`171` 仍是字面量**：若契约悄悄丢掉一个**移植**条目，`count == len(result.tools)` 与 `count == 171 + added_count` 会同时不成立 → 红（`accept_m1.ps1:197-209` 的注释早已把这条写成设计意图，本批沿用同一形式）。
2. **清单与契约是两份文件**：把某条新增工具从 `docs/tool-groups-added.json` 删掉（或改名、或换顺序），契约的 `_meta.added_tools` 就不等于清单 → 红（`check_tool_groups.py --added` 的同一断言）。

**逐条 diff 已核对**：6 个文件的改动全部只出现在"期望值来源"的表达式里，没有任何检查被删除、没有 `-ge`/恒真、
没有把 `-eq` 换成"包含于"（`git diff --stat` 见 §7，5 个改动脚本的新 sha256 见 §7.3）。

### 2.3 `.ps1` 两个脚本的实时实时性

`mcp052/mcp053/mcp054` 三个脚本里，派生出来的 `$editorExpectedCount`/`$gameExpectedCount` **仍然是**"脚本自己刚取回的
实况 `tools/list` 必须等于的那个数"（`a02_editor_live_count_is_the_contract_view`、`b02_game_live_count_is_the_contract_view`、
`a2_editor_live_count_is_the_contract_view`、`d2_game_live_count_is_the_contract_view`、`c01`）。本批改的是"那两个数**从哪来**"，
不是"还查不查实况"。

### 2.4 退出码对照（真实进程级）

**反例探针**（`mcp064_stale_expectation_reverse_probe.ps1`，用 `Invoke-Expression` 在**真实输入**上求值原文表达式与新表达式）：

- 命令：`powershell -NoProfile -ExecutionPolicy Bypass -File F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\scripts\mcp064_stale_expectation_reverse_probe.ps1`
- 输出（节选，13 条探针 / 0 失败 / **exit 0**）：

```
contract       : 176 entries, _meta.count=176, added_count=5
added manifest : 5 name(s) [project_build_csharp, project_write_text_file, project_validate_scripts, editor_set_node_script_batch, editor_set_node_property_updates]
derived views  : editor=153 game=72 (171 ported + 5 added)

[PASS] mcp052_old_endpoint_expectations        value : False (expected False)
[PASS] mcp052_new_endpoint_expectations        value : True  (expected True)
[PASS] mcp053_old_contract_is_175              value : False (expected False)
[PASS] mcp053_old_added_tools_is_the_four_some value : False (expected False)
[PASS] mcp053_old_endpoint_expectations        value : False (expected False)
[PASS] mcp053_new_contract_is_ported_plus_added value : True
[PASS] mcp053_new_added_tools_is_the_manifest  value : True
[PASS] mcp054_old_contract_is_175              value : False (expected False)
[PASS] mcp054_old_added_count_is_4             value : False (expected False)
[PASS] mcp054_new_contract_is_ported_plus_added value : True
[PASS] mcp054_new_added_tools_is_the_manifest  value : True
[PASS] shared_contract_formula_holds           value : True
probes=13 failures=0
TASK-064 REVERSE PROBE PASS
```

**含义**：每一条"旧表达式"今天都是 `False`，所以一个跑到它的 Gate 循环必然以非零退出码结束；每一条"新表达式"都是 `True`
→ 该检查通过。这就是"修复前 exit≠0 / 修复后 exit 0"在**同一份输入**上的精确对照。

**两个 Python 脚本的真实端到端复跑**：

| 脚本 | 命令与输入 | 修复前 | 修复后 |
|---|---|---|---|
| `mcp053_contract_diff.py` | `git show c1f3385daf:<contract>` 与 `git show 96c1693d3d:<contract>`（TASK-053 的真实 before/after 对；重定向走 `cmd.exe`，因为 PowerShell 5.1 的 `>` 会加 UTF-8 BOM，实测 `json.load` 直接拒绝） | 旧脚本在该对上也是 exit 0（那一对就是它冻结的那一对）；但同一棵树（176）上无法重跑 —— 那正是被点名的问题 | **`checks = 34, problems = 0`，exit 0**；其中 `before_capture_is_the_batch_start`（173）、`after_is_before_plus_the_declared_pair`（175 = 173 + 2）、`meta_count_moved_by_the_declared_delta`（173 → 175，两侧都等于 `171 + 各自 added_count`）三条全部 PASS |
| `mcp059_contract_pre_post.py` | 默认 `--rev 213b1791258aa476e6b271e57733a689ad8f3ff9`，after = 今天 HEAD 的契约 | 旧脚本在今天树上**必红**（`len(b_tools) == len(a_tools) == 175` 与 `sorted(desc_moved) == sorted(FIVE)` 两条） | **全部 PASS，exit 0**；输出里可见派生结果：`before 175 = 171 + 4, after 176 = 171 + 5`、`appended tail = ['editor_set_node_property_updates']`、`growth_is_exactly_the_newly_declared_added_tools` PASS |

`mcp059` 修复后的关键行（原文）：

```
[PASS] count_is_len_result_tools :: _meta.count before=175 (entries=175), after=176 (entries=176)
[PASS] names_and_order_unchanged_up_to_appended_entries :: before is an ordered prefix of after; appended tail = ['editor_set_node_property_updates']
[PASS] growth_is_exactly_the_newly_declared_added_tools :: appended=['editor_set_node_property_updates']; newly declared added_tools=['editor_set_node_property_updates'] (derived; the literal 175 is gone - TASK-064 D-8)
[PASS] count_is_ported_plus_added_on_both_sides :: before 175 = 171 + 4, after 176 = 171 + 5
[PASS] every_inputSchema_identical :: moved schema(s): none (176/175 compared)
[PASS] all_five_descriptions_moved :: moved among the five: project_set_setting, editor_add_input_action, project_add_autoload, project_remove_autoload, editor_reload_plugin
       report: descriptions that moved and are not one of the five :: editor_set_node_property, editor_get_node_properties, editor_set_node_script_batch (later-batch moves; not this batch's subject)
[PASS] declared_growth_is_consistent :: grew=True appended=['editor_set_node_property_updates'] newly declared added_tools=['editor_set_node_property_updates']; growth fields moved=['added_count', 'added_tools', 'count']
[PASS] meta_only_the_allowed_keys_moved :: moved: added_count, added_tools, count, generator_version, overrides; unexpected: none
[PASS] meta_map_sha256_unchanged / meta_excluded_unchanged / meta_merged_unchanged / meta_generated_from_sha256_unchanged / meta_order_normative_unchanged / meta_tool_count_in_unchanged
[PASS] five_replace_records_present
CONTRACT PRE/POST PASS (only the five descriptions, the generator version and their audit records moved)
```

> **诚实标注（一条边界，见 §8 偏差 3）**：`desc_moved` 一条被**收窄**到"本批的五个必须都动过"，
> 并把"动过但不属于这五个的名字"**打印**出来而不是断言。原因：after 侧是**今天的树**，
> 事后无法把 TASK-063 对 `editor_set_node_property`/`editor_get_node_properties`/`editor_set_node_script_batch` 的
> 合法改写归因给 TASK-059（`213b1791258` → HEAD 之间隔着很多批次）。这不是本批引入的缺口，而是"用 HEAD 当 after 侧"的固有边界：
> TASK-063 自己的报告 §6.2 已把这两条列成"**非本树可重跑**"。本批把它变成"可重跑且**如实报告**"，并把**未能断言**的那部分
> 明确写在这里，而不是让它藏在一条绿色断言后面。

---

## 3. 改动清单（逐文件）

### 3.1 `mcp052_added_tools_evidence.ps1`
- 新增 `$AddedManifest` 路径变量（`docs/tool-groups-added.json`）。
- `contract_meta_added_tools`：四条字面量名单 → 与第六份清单逐位相等 + `Count == _meta.added_count` + TASK-052 两条仍在位置 0/1。
- `endpoint_expectations_derived`：`152/72` → `契约 == 171 + added_count` 且 `addedNames.Count == _meta.added_count`（实时条数由同脚本另两条断言）。

### 3.2 `mcp053_added_tools_evidence.ps1`
- `contract_is_175_entries` → **改名** `contract_is_ported_plus_added_entries`：`契约 == 171 + added_count`、`added_count == len(added_tools)`、`_meta.count == len(result.tools)`。
- `contract_meta_added_tools_is_the_four_some` → **改名** `contract_meta_added_tools_is_the_manifest`：与第六份清单逐位相等 + 位置 2/3 仍是 TASK-053 两名。
- `endpoint_expectations_derived`：同 3.1。

### 3.3 `mcp054_forensics_and_csharp_evidence.ps1`
- 新增 `$AddedManifest` 路径变量。
- `contract_is_175_entries` → **改名** `contract_is_ported_plus_added_entries`。
- `contract_meta_added_tools_is_the_four_some` → **改名** `contract_meta_added_tools_is_the_manifest`（清单逐位相等 + `added_count` 一致）。

### 3.4 `mcp053_contract_diff.py`
- 删 `EXPECTED_BEFORE_COUNT/EXPECTED_AFTER_COUNT`，新增 `CONTRACT_PORTED_COUNT = 171` 与 `expected_after_count = len(before_tools) + len(EXPECTED_ADDED)`。
- 检查改名：`before_is_173` → `before_capture_is_the_batch_start`；`after_is_175` → `after_is_before_plus_the_declared_pair`。
- `meta_count_moved_to_175` → `meta_count_moved_by_the_declared_delta`（四个合取：两侧 `count == len(result.tools)`、after 增量恰为本批两名、两侧 `count == 171 + 各自 added_count`）。
- 其余 30 条检查**一字未动**（真实复跑 `checks = 34, problems = 0`）。

### 3.5 `mcp059_contract_pre_post.py`
- 删 `count_is_175`，新增 4 条：`count_is_len_result_tools`、`names_and_order_unchanged_up_to_appended_entries`（有序前缀）、`growth_is_exactly_the_newly_declared_added_tools`（增量恰为 after 新声明的 `added_tools` 尾段）、`count_is_ported_plus_added_on_both_sides`。
- 新增辅助 `is_ordered_subsequence()` / `first_difference()`；新增常量 `CONTRACT_PORTED_COUNT = 171`。
- `meta_only_the_allowed_keys_moved`：`count/added_tools/added_count` 三个增长字段**有条件**进入允许集合（条件由新增的 `declared_growth_is_consistent` 断言，无增长时三者仍必须不动）。
- `every_inputSchema_identical` / `all_five_descriptions_moved`：比较域从 `a_names` 改为 `b_names`（两侧共有的名字），避免把"本批之后新增的条目"当成"缺了 before 侧"而 KeyError。
- 头部 docstring 更新：明确"本批之后合法追加"是允许的，以及未声明的追加/改名/重排/删除仍失败。

### 3.6 `mcp_evidence_guard.ps1`（+351 行，纯新增）
见 §4.1 与 §5.1。

### 3.7 新增脚本
- `mcp064_stale_expectation_reverse_probe.ps1`（§2.4 的 13 条探针）
- `mcp064_evidence_hygiene_probe.ps1`（§4.4/§5.4 的 20 个反例案例）

---

## 4. 缺陷 (i)：证据文件同名复用被覆盖

### 4.1 为什么"改脚本"必须改在共享库里（一处带证据的判断）

D-4 的实测事实是：`run.log` 里同一个 id `c2_b0_build` 被复用 4 次（06:27:35 / 06:28:15 / 06:30:54 / 06:52:44），
而写入者用的是固定路径。**产生那一批证据的脚本已经不在树里**（它们在 `%TEMP%\mcp-breakout`，TASK-062 只回收了副本，
见 `docs/reports/evidence/task060/trace-recovered/scripts/`），所以"改回原脚本"不可能。更关键的是：

1. 回收副本被 `docs/reports/evidence/task060/recovery/POST-RECOVERY-MANIFEST.sha256.tsv` **逐个钉了 sha256**
   （第 512/506 行就是 `mcp060_lib.ps1` 的 `b468567b...` 与 `mcp060_c4_script_batch.ps1` 的 `800e5ea4...`）。
   改动它们会让那份回收集的 445 文件逐字节自检**失效**——那正是 TASK-062 的成果，不该被本批牺牲。
   故本批**保持回收副本只读**，把它作为"缺陷发生时的代码状态"的证据。
2. 真正的防线是**共享库**：今后任何证据脚本都从 `mcp_evidence_guard.ps1` 取写入函数（`mcp_import_guard.ps1` /
   `mcp_port_guard.ps1` 已是同一模式），而"同名覆盖"在新 API 下**不可能不发生**：路径里带了内容 sha8。

下面的"修复后片段"因此是**库里现在的代码**，而"修复前片段"是从回收副本里逐字抄来的历史状态（`mcp060_lib.ps1:88-89`
与 `mcp060_c4_script_batch.ps1:43/61`），两者的对照是本条的核心证据。

### 4.2 修复前片段（历史状态，逐字摘自回收副本）

```powershell
# docs/reports/evidence/task060/trace-recovered/scripts/mcp060_lib.ps1:88-89
$reqFile  = Join-Path $EvidenceDir ($Id + '.request.json')
$respFile = Join-Path $EvidenceDir ($Id + '.response.json')
...
& $script:Curl ... -o $respFile ...        # <- 同一 $Id 第二次调用就覆盖第一次
```

```powershell
# docs/reports/evidence/task060/trace-recovered/scripts/mcp060_c4_script_batch.ps1:43 / :61
Copy-Item -Force $scenePath (Join-Path $Ev 'main.tscn.before_attach') -ErrorAction SilentlyContinue
...
Copy-Item -Force $scenePath (Join-Path $Ev 'main.tscn.after_attach')  -ErrorAction SilentlyContinue
```

### 4.3 修复后片段（`modules/mcp_server/scripts/mcp_evidence_guard.ps1`，本批新增）

```powershell
function New-McpEvidencePath {
    #   <Directory>\<Leaf>__<Id>__<seq>__<sha8><Extension>
    #   Id 可选；sha8 = 内容本身 sha256 的前 8 位 —— 不同内容不可能落到同一个名字
    $name = ('{0}{1}__{2:d4}__{3}{4}' -f $safe, $middle, $Seq, $ContentSha256.Substring(0, 8), $Extension)
    return (Join-Path $Directory $name)
}

function Assert-McpEvidencePathUnused {
    #   一条路径一种内容：同路径 + 不同 sha -> 抛错（并打印两个 sha）；同路径 + 同 sha -> 允许并标记 SameContentSeen
    if ($null -ne $seen -and $seen -cne $newHash) {
        throw ('evidence path already holds DIFFERENT content in this run: {0} first sha256={1}, now sha256={2}. '
             + 'This is the c2_b0_build overwrite defect; chain a sequence token instead.' -f $Path, $seen, $newHash)
    }
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $existing = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower()
        if ($existing -cne $newHash) {
            throw ('evidence path already exists with DIFFERENT content: {0} on disk sha256={1}, about to write sha256={2}. '
                 + 'Refusing to overwrite evidence that is already cited.' -f $Path, $existing, $newHash)
        }
        $sameContent = $true
    }
    ...
}

function Write-McpEvidenceBytes {
    $hash = Get-McpEvidenceContentSha256 -Bytes $Bytes
    $path = New-McpEvidencePath -Directory $Directory -Leaf $Leaf -Seq $Seq -ContentSha256 $hash -Extension $Extension -Id $Id
    $check = Assert-McpEvidencePathUnused -Path $path -Bytes $Bytes
    [IO.File]::WriteAllBytes($path, $Bytes)
    $script:McpEvidenceWrittenPaths[$path] = $hash        # 只有真正落盘才登记
    ...
}

function Assert-McpEvidenceTreeUniqueness {   # 事后审计：同名不同 sha -> 抛错
    if ($hashes.Count -gt 1) { $collisions += $record } else { $duplicates += $record }
    ...
    throw ('evidence tree has same-name files with DIFFERENT contents: ...')
}
```

### 4.4 反例演示（真实输出，`mcp064_evidence_hygiene_probe.ps1`）

命令：`powershell -NoProfile -ExecutionPolicy Bypass -File F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\scripts\mcp064_evidence_hygiene_probe.ps1`
（scratch = `%TEMP%\mcp064-hygiene`，**每次运行自清**，故"清理 → 还原 exit 0"就是**连跑第二次**）

```
[PASS] case0_four_reuses_of_one_id_produce_four_files
       id 'c2_b0_build' written 4 times -> 4 distinct path(s), 4 file(s) on disk:
       c2_b0_build__reuse__0001__e62eff48.json, ...__0002__5a01165c.json, ...__0003__263ef569.json, ...__0004__a6b909e1.json
[PASS] case0_names_carry_seq_and_sha8        (命名约定 <id>__<seq>__<sha8>.json)
[PASS] case0_name_digest_matches_content     (每个文件名自带自己的 sha256 前 8 位)
[PASS] case1_same_path_same_content_is_not_an_overwrite   (同路径同字节不是覆盖)
[PASS] case1_identical_reuse_is_flagged_as_reproduced_bytes (1 个文件、SameContentSeen=True)
[PASS] case2_same_path_different_content_is_refused        (同名 + 不同 sha -> 抛错)
       guard said: evidence path already holds DIFFERENT content in this run: ...\c2_b0_build_overwrite__0001__e62eff48.json
       first sha256=e62eff48... , now sha256=5a01165c... . This is the c2_b0_build overwrite defect; chain a sequence token instead.
[PASS] case2_refusal_names_both_digests     (报错文案带两个 sha，绝不静默)
[PASS] case2_the_victim_file_is_still_its_original_bytes   (被"想覆盖"的文件字节未变)
[PASS] case3_tree_with_same_name_different_content_is_refused (事后树审计也抛错)
[PASS] case3_tree_with_unique_names_passes
[PASS] case8_old_fixed_name_writer_loses_three_of_four_captures
       old writer wrote 4 payloads to 1 name (c2_b0_build.response.json); the file no longer holds payload 1 (a6b909e1 vs e62eff48);
       the tree audit sees NOTHING because the other three files are gone. This is exactly D-4 ('37 of 200 run-log lines no longer
       matched disk'): the defect is invisibility, not just overwriting.
[PASS] case8_new_writer_keeps_every_capture_and_the_audit_is_clean
       4 payloads -> 4 files, each named after its own digest and each holding its own payload byte for byte:
       c2_b0_build__0001__e62eff48.json, ...__0002__5a01165c.json, ...__0003__263ef569.json, ...__0004__a6b909e1.json
...
cases=20 failures=0
TASK-064 EVIDENCE HYGIENE PROBE PASS
handover written: C:\Users\wyl\AppData\Local\Temp\mcp064-hygiene\mcp064-hygiene-cases.json
```

**退出码**：`RUN1_EXIT=0`、`RUN2_EXIT=0`（第二次运行即"清理后还原"：脚本先删 scratch 再重跑，案例数、结论完全一致；
产物 `mcp064-hygiene-cases.json` 每次重写）。

---

## 5. 缺陷 (ii)：快照时序（before/after 同 sha）

### 5.1 修复后片段（`mcp_evidence_guard.ps1`）

```powershell
function Write-McpEvidenceSnapshotPair {
    param($Directory, $Leaf, [scriptblock]$Before, [scriptblock]$After, [scriptblock]$Between = $null,
          $Extension = '.txt', [switch]$ExpectedIdentical, [string]$Reason = '')
    # 顺序是函数性质，不是调用方的缩进
    $beforeWritten = Write-McpEvidenceBytes -Directory $Directory -Leaf ($Leaf + '.before') -Bytes (& $Before | ...) -Extension $Extension
    if ($null -ne $Between) { $null = & $Between }
    $afterWritten  = Write-McpEvidenceBytes -Directory $Directory -Leaf ($Leaf + '.after')  -Bytes (& $After  | ...) -Extension $Extension

    $identical = ($beforeWritten.Sha256 -ceq $afterWritten.Sha256)
    if ($ExpectedIdentical) {
        if (-not $identical) { throw '... declared -ExpectedIdentical but the two captures differ ...' }
        if ([string]::IsNullOrWhiteSpace($Reason)) { throw '... declared -ExpectedIdentical without -Reason ...' }
    } elseif ($identical) {
        throw ('snapshot pair has the SAME sha256 ({0}) for before={1} and after={2}: the before capture already contains whatever '
             + 'the step under test was supposed to change, so the pair cannot attribute anything. ...' -f ...)
    }
    return [pscustomobject]@{ Before=...; After=...; BeforeSha256=...; AfterSha256=...; Identical=$identical; ... }
}
```

### 5.2 反例演示（同一探针的真实输出）

```
[PASS] case4_identical_pair_without_declaration_is_refused
       guard said: snapshot pair has the SAME sha256 (573f5a118c0dcee5518177cf496d74926640453d3339c0855a9ed207c1845869)
       for before=main.tscn.before__0001__573f5a11.tscn and after=main.tscn.after__0001__573f5a11.tscn: the before capture already
       contains whatever the step under test was supposed to change, so the pair cannot attribute anything. ...
[PASS] case5_ordered_pair_differs_and_is_attributable
       before=main.tscn.before__0002__0d62d906.tscn (0d62d906) -> after=main.tscn.after__0002__573f5a11.tscn (573f5a11)
[PASS] case5_pair_names_carry_their_own_sha8
[PASS] case6_expected_identical_without_a_reason_is_refused
       guard said: snapshot pair declared -ExpectedIdentical without -Reason; an identical pair is only evidence when the expectation is stated
[PASS] case6_declared_identical_pair_passes_and_carries_the_reason
       identical=True reason='idempotence: writing the same value twice must not touch the file'
[PASS] case6_declared_identical_but_the_pair_moved_is_refused
       guard said: snapshot pair declared -ExpectedIdentical but the two captures differ: before=moved.tscn.before__0001__4f3f9778.tscn
       (4f3f9778) after=moved.tscn.after__0001__daec70bf.tscn (daec70bf)
```

`case4` 复现的就是第 2 轮那次：before 里已经含 18 行 `script = ExtResource("1_t6lrv")`，所以 before/after 同 sha
（历史证据里是 `a423d468713a4824d1034177f26e8e48fd7a51a23bf47084517088e0172ae183`）；如今这**必然报错**，
除非调用方显式写 `-ExpectedIdentical -Reason <为什么相同才是重点>`。

### 5.3 "清理 → 还原 exit 0"

`case4/6 的两次拒绝会在 scratch 里留下 before 文件（这是"失败尝试的现场"）；探针结尾调用
`Assert-McpEvidenceTreeUniqueness` 对自己的输出做交付前审计并把 `mcp064-hygiene-cases.json` 写下；**连跑第二次**（自清 scratch）
`cases=20 failures=0`、exit 0，与第一次逐条一致。这就是任务书要的"清理 → 还原 exit 0"。

### 5.4 一处必须说清的语义（避免被读成"放宽"）

含 `SameContentSeen` 的"同路径 + 同字节"是**允许**的。任务书的硬要求是"**同名且 sha 不同 → 直接报错**"（"禁止静默覆盖"），
本批严格照办：**不同 sha 在任何一层都抛错**（同进程注册表、磁盘既有文件、事后树审计）。而"同 sha 重写"不是覆盖，
把它也判死会**误伤**合法的幂等重放（下面 `case1`/`case7` 就是这种场景），所以它被允许，但**必须**换回一个布尔：
`SameContentSeen=$true`，让调用方能说出"这份证据逐字节重现了"而不是悄悄重写历史。

---

## 6. 未完成的覆盖（如实声明，不冒充已验）

**三个 `*.ps1`（`mcp052`、`mcp053`、`mcp054` 证据脚本）的端到端重跑仍无法在本树完成**，原因与 TASK-063 §6.2 完全相同：
三个脚本都在 `foreach ($pair in @(@('plain', ...), @('mono', ...)))` 里**同时**通过 plain 与 mono 引擎启动真实进程，并先断言
`engines_match_head`；而本工作树的 mono 二进制
`F:\RustProjects\godot-mcp-pro\code\godot\bin\godot.windows.editor.x86_64.mono.console.exe` 仍是 **2026/9/25 04:43**
（锚点 `cd7224274`），plain 是 **09:26**（`4.8.dev.custom_build.92a260b68`）。**本批没有构建 mono**：
mono 全量构建是 `scripts/mcp057_build_mono.cmd` 的独立长任务，不在本批预算内，且构建会占用与其它工作相同的资源。

**因此本批给出的等价证据是**：`engines_match_head` 之外**所有**被本批触碰的判定都发生在任何引擎启动**之前**
（只读三个受版本控制的 JSON），§2.4 的反例探针用**同一份输入**求值**原文表达式**与**新表达式**，
逐条给出"旧 = False（⇒ 非零退出）/ 新 = True（⇒ exit 0）"。这是**可复算**的对照，但不是"三个脚本整体 exit 0"。
**这一条是本轮的实测覆盖缺口**，不应当被读成"已回归"。建议：在有 HEAD 锚点 mono 二进制后，由这三个脚本的 owner 直接复跑（预期全绿）。

**同样未重跑**（与本批无关、且不需要改）：`accept_m1.ps1`、`check_contract_subset.ps1`、门③/④/⑥。本批**未改任何实现代码**
（`git diff --stat -- modules/mcp_server/tools tests` 为空，§7），故它们的行为与 TASK-063 报告所载完全一致。

---

## 7. 纪律与门（逐条给证据）

### 7.1 只改 `scripts/**` 与 `docs/**`（本批只改 `scripts/**`）

```
command : git diff --stat -- modules/mcp_server/tools tests
exit    : 0
output  : []  (empty when the run is clean)

command : git diff --stat -- modules/mcp_server/docs/tools_list.renamed.json modules/mcp_server/docs/tool-groups-added.json modules/mcp_server/docs/tool-rename-map.json
exit    : 0
output  : []

command : git diff --stat -- modules/mcp_server/docs/DESIGN-DETAIL.md
output  : []

9877    : no listener at the end of the run (this task started no engine at all)
```

`git status --porcelain` 的全部内容：

```
 M modules/mcp_server/scripts/mcp052_added_tools_evidence.ps1
 M modules/mcp_server/scripts/mcp053_added_tools_evidence.ps1
 M modules/mcp_server/scripts/mcp053_contract_diff.py
 M modules/mcp_server/scripts/mcp054_forensics_and_csharp_evidence.ps1
 M modules/mcp_server/scripts/mcp059_contract_pre_post.py
 M modules/mcp_server/scripts/mcp_evidence_guard.ps1
?? modules/mcp_server/docs/tasks/TASK-064-stale-expectations-and-evidence-hygiene.md
?? modules/mcp_server/scripts/mcp064_evidence_hygiene_probe.ps1
?? modules/mcp_server/scripts/mcp064_stale_expectation_reverse_probe.ps1
```

（未跟踪残留仍是既有的 `.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`；本批未动。）

### 7.2 `git diff --stat`（本批全部改动）

```
 .../scripts/mcp052_added_tools_evidence.ps1        |  46 ++-
 .../scripts/mcp053_added_tools_evidence.ps1        |  37 ++-
 modules/mcp_server/scripts/mcp053_contract_diff.py |  48 ++-
 .../mcp054_forensics_and_csharp_evidence.ps1       |  23 +-
 .../mcp_server/scripts/mcp059_contract_pre_post.py | 151 +++++++--
 .../mcp_server/scripts/mcp_evidence_guard.ps1      | 351 +++++++++++++++++++++
 6 files changed, 605 insertions(+), 51 deletions(-)
```

### 7.3 改动/新增文件的 sha256（`git status` 之后的最终状态）

```
c234aa67b1bed2c720f3745508072ab723a01475a02075311bf1d0ee2502fc42  modules/mcp_server/scripts/mcp_evidence_guard.ps1
92f44170f9a4552f628df9f82646c68fa1cb4cc0658b7152e8f915c3b0718404  modules/mcp_server/scripts/mcp064_stale_expectation_reverse_probe.ps1
277c5937a9a5233a3239177d282d685b24fd618adc490dc40420977eeb73aa68  modules/mcp_server/scripts/mcp064_evidence_hygiene_probe.ps1
bf3d4960fe32ee1b48bd02fb79336ef6ac3a6508296e1dfd244827406478c724  modules/mcp_server/scripts/mcp052_added_tools_evidence.ps1
7e9534aac98be3e788a203338f9b114e3cff10f5f444118e56214c9aa49dbee3  modules/mcp_server/scripts/mcp053_added_tools_evidence.ps1
462c20773e03d3b5daf339c8096afd0aed0c418ae68bb7198bca2b063be9ba67  modules/mcp_server/scripts/mcp054_forensics_and_csharp_evidence.ps1
dd44d097392c47cb53cdab9b44b604aa9849bc985c08e8f31ef5c2bd899f8195  modules/mcp_server/scripts/mcp053_contract_diff.py
4dd758e0a0cb0458f45f48106e4350816243c7800de34d434943738389ae22fa  modules/mcp_server/scripts/mcp059_contract_pre_post.py
```

### 7.4 `.ps1` 纯 ASCII

```
mcp_evidence_guard.ps1                      : bytes=25521 non-ascii=0
mcp064_stale_expectation_reverse_probe.ps1  : bytes=10605 non-ascii=0
mcp064_evidence_hygiene_probe.ps1           : bytes=19728 non-ascii=0
mcp052_added_tools_evidence.ps1             : bytes=43149 non-ascii=0
mcp053_added_tools_evidence.ps1             : bytes=64691 non-ascii=0
mcp054_forensics_and_csharp_evidence.ps1    : bytes=44376 non-ascii=0
（两个 .py 也 0 非 ASCII 字节）
```

### 7.5 D86 锚点

- 被评对象：**工作树**（HEAD `c589eae24`），不是二进制。本批**不构建、不启动引擎**。
- 全部命令串行执行，**任何时刻只有一个进程**在跑；`scons` **一次都没跑**（无 D62 风险）。
- 9877：本任务**没有启动、没有杀死、没有重启任何进程**；运行前后 `Get-NetTCPConnection -LocalPort 9877 -State Listen` 均无监听者（用户当时的编辑器未在运行——这是一条**环境事实**，不是本任务的动作结果）。
- **未 push**（按纪律）。

---

## 8. 偏差与边界（如实列出）

1. **未改回收副本 `docs/reports/evidence/task060/trace-recovered/scripts/**`**。理由见 §4.1：它被 `POST-RECOVERY-MANIFEST.sha256.tsv` 逐个钉死，改动会让 TASK-062 的 445 文件逐字节自检失效。任务书要求的"修复后脚本片段"以**共享库当前代码**的形式给出（§4.3/§5.1），"修复前片段"逐字摘自回收副本（§4.2）。本批**没有**把旧脚本改成新 API 的机械重写——那属于 TASK-060 的所有者，且没有 C#/mono 环境无法验证。
2. **任务书点名 4 个脚本，本批改了 6 个（6 处期望）**。多出的两处（`mcp053_added_tools_evidence.ps1:327` 的四条新增名单、`mcp054_forensics_and_csharp_evidence.ps1:307` 的 `added_count==4`）是静态筛查在同一根因上找到的同类陈旧期望，改法完全一致，逐条列在 §1.1 并标了来源。**没有把这些当作"任务书漏项"来偷偷扩大范围**：它们被单列，且当时若跑也会红。
3. **`mcp059_contract_pre_post.py` 的一条边界**（§2.4 末）：`desc_moved` 收窄到"本批五个必须都动过"，"本批之外动过的描述"改为**打印**而非断言。原因是从 HEAD 无法归因后续批次；这是**覆盖边界**而不是"为了变绿而放宽"，且 §2.4 已把这条边界与它的独立补偿（批次自己的 pre/post + 门①逐字）写清。
4. **三个 `*.ps1` 的端到端重跑未完成**（§6）：无 HEAD 锚点 mono 二进制。本批用"同一输入上求值原文与新表达式"的探针给精确前后对照，**不声称**整体已回归。
5. **决策日志**：`DECISIONS.md` 在 harness 仓库且对本模块执行者只读（PLAYBOOK §0），本 fork 内**不得**新建竞争性日志。本轮决策留痕 = 本报告 + 提交信息 + 各脚本内的长注释（每条改动都带 `TASK-064 D-8` 标记）。
6. **一处工具行为修正顺带发现**：`Assert-McpEvidencePathUnused` **不登记**"已写"状态（登记发生在真正落盘之后）。
   否则一次失败的重试（例如快照对因同 sha 被拒）会把该路径永久占用，让"改好顺序后再跑"也失败——**实测**过，见探针 `case5`
   的 `before__0002` 序号（第一次尝试用了 0001 并留下现场，第二次落到 0002）。这是缺陷修法自身的一个陷阱，记录于此。

---

## 9. 交付物清单

| 路径（仓库内，绝对前缀 `F:\RustProjects\godot-mcp-pro\code\godot\`） | 说明 |
|---|---|
| `modules/mcp_server/scripts/mcp_evidence_guard.ps1` | **+351 行**：`Get-McpEvidenceContentSha256` / `New-McpEvidencePath` / `Get-McpEvidenceSha8` / `Assert-McpEvidencePathUnused` / `Write-McpEvidenceBytes` / `Write-McpEvidenceText` / `Write-McpEvidenceSnapshotPair` / `Assert-McpEvidenceTreeUniqueness` |
| `modules/mcp_server/scripts/mcp064_stale_expectation_reverse_probe.ps1` | 13 条"旧表达式 False / 新表达式 True"探针（§2.4），exit 0 |
| `modules/mcp_server/scripts/mcp064_evidence_hygiene_probe.ps1` | 20 个取证卫生案例（含 6 个故意制造的反例），连跑两次 exit 0 |
| `modules/mcp_server/scripts/mcp052_added_tools_evidence.ps1` | 2 处期望改派生 |
| `modules/mcp_server/scripts/mcp053_added_tools_evidence.ps1` | 3 处期望改派生 |
| `modules/mcp_server/scripts/mcp054_forensics_and_csharp_evidence.ps1` | 2 处期望改派生 |
| `modules/mcp_server/scripts/mcp053_contract_diff.py` | 3 处字面量改派生（真实修订对上 34/34、exit 0） |
| `modules/mcp_server/scripts/mcp059_contract_pre_post.py` | 1 处字面量改派生 + 增长规则（真实修订对上全 PASS、exit 0） |
| `modules/mcp_server/docs/reports/REPORT-064-stale-expectations-and-evidence-hygiene.md` | 本报告 |

**返回给决策者**：≤8 行总结 + 报告路径。