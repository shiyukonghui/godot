# REPORT-068 — 收口登记项：陈旧期望派生 + 两处描述澄清（契约 sha 只移动一次）+ 报告勘误

> 任务书：`docs/tasks/TASK-068-registered-items.md`；手册：`docs/tasks/PLAYBOOK-group-port.md`。
> 来源：`REPORT-067-script-listing-and-editor-save.md` §⑦ 与 `DECISIONS.md` D125 裁决 (a)–(d)。
> 本报告的全部结论只在下表锚点上成立（D86）。

## 0. 元信息与锚点（D86）

| 项 | 值 |
|---|---|
| 角色 / 任务 | 实现工程师 / TASK-068 |
| 状态 | **完成**：三件事全做完（① 陈旧期望派生 + 普查；② 两处描述澄清 + 契约重生成 + C++ 同步；③ R4 §8.3 追加勘误）；六道门 + 三个契约机器检查全部 exit 0；`accept_m1` ×2 清单一致；无阻塞 |
| **工作树锚点** | `git rev-parse HEAD` = **`eff591a1404737f34605183d9047d40477ae55e1`**（`--short=9` = `eff591a14`）；本批**未提交**（父层决定），交付时工作树 = HEAD + 下表 8 个 ` M ` + 本批新增文件（9 个脚本 + 报告 + 证据树 + 任务书） |
| **二进制锚点** | plain `bin\godot.windows.editor.x86_64.console.exe` = `4.8.dev.custom_build.eff591a14`；mono `bin\godot.windows.editor.x86_64.mono.console.exe` = `4.8.dev.mono.custom_build.eff591a14`。**两者都 `--version == HEAD`**（§5.1 打印）。构建严格串行（§5.1）：step0 plain → red plain → green plain → mono |
| **契约** | `docs/tools_list.renamed.json` = **`701539829ed8fcaa227f280fb6bff71b96522248cd9c4b84f2073c27eb17cfe0`**（155872 B；基线 `d4e53b43840b…` / 152873 B → **本批移动一次**，条数 **176 不变**）。全 10 项指纹见 §5.6 |
| **端口纪律** | 9877 在本批**每一次**活运行前后都断言无监听（§3.4 的 `p0/p9_port_9877_free_*`）；只用 9888/9889；只 stop 本脚本 `Start-Process` 的 PID |
| **禁止 push** | 未 push；未做任何提交 |
| **构建纪律** | 从 **cmd** 启动；全程**只有一个 scons 进程**；`build_local.cmd` / `mcp057_build_mono.cmd` 自己把 scons 输出重定向到 `%TEMP%` 日志（不抑制、不经管道）；**mono 与 plain 严格串行** |
| **`.ps1` 纯 ASCII** | 本批新增的 4 个 `.ps1` 全部纯 ASCII（中文只出现在 `String::utf8(...)` 的 C++ 与 Python 源里，或由码点构造，见 §2.4） |
| **红相位输出当场保存** | `docs\reports\evidence\task068\logs\red_plain_task068.txt`（§3.1 逐字） |
| **证据前缀（绝对路径）** | `F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task068\` |
| **改动文件（8 个 ` M `，+371 / −14）** | `docs/scripts/check_rename_map.py`、`scripts/gen_renamed_contract.py`、`docs/tools_list.renamed.json`、`docs/tool-groups-added.json`、`tools/project_read_files.cpp`、`tools/running_game_test_execution.cpp`、`tests/test_mcp_server.h`、`docs/reports/BREAKOUT-FINDINGS-R4.md`（§5.6 的 `git diff --stat` 逐字） |
| **新增文件** | `scripts/{check_hardcoded_counts,mcp068_contract_cpp_diff,mcp068_contract_fingerprint,mcp068_bump_added_manifest,mcp068_fix_added_entries}.py`、`scripts/{mcp068_env,mcp068_live,mcp068_rename_map_reverse_probe,mcp068_exitcodes}.ps1`、`docs/reports/REPORT-068-registered-items.md`（+ 证据树 `evidence/task068/**`、任务书本身） |
| **只允许改 `modules/mcp_server/**`** | 本批**没有**改任何引擎文件（TASK-067 的 `core/config/*`、`editor/editor_node.cpp` 本批一字未动）；hof-rs **只读**；`docs/DESIGN-DETAIL.md` **未改**；**未 push** |

---

## 0.1 一句话结论

| # | 任务书要求 | 结论 | 关键数字 |
|---|---|---|---|
| ① | `check_rename_map.py` 仍硬编码 171 → 改为派生（保留 171 为被检查字面量），给退出码对照 + 反向探针；顺手普查 `scripts/**` 同类硬编码 | **已改（派生），171 保留为 checked literal** | 修复前 exit **1**（G1/G5 **恰好 2 条** FAIL）；修复后 exit **0**；反向探针 **7/7 PASS**、exit 0；普查 **147** 处、**0** UNCLASSIFIED |
| ② | 两处描述澄清走 `DESCRIPTION_OVERRIDES` + 生成器递增 + 重生成 + 全部指纹 + 门①逐字 | **已做**（v1.20.0；契约 **176 不变**，sha 只移动一次） | overrides **31 → 33**；契约 sha `d4e53b43…` → **`70153982…`**；门① 两端口 6 条 `name/description/inputSchema` 全 True |
| ③ | `BREAKOUT-FINDINGS-R4.md` §8.3 的 `.dll` 字节数陈旧 → **追加勘误**（append-only） | **已追加「附录 A」** | 原文 `19968 B` 保留；实测 **20992 B** / `2e1ff3dd…`（独立复算）；不改原文的三条理由见 §4.3 |
| 契约条数 | 本批**条数不变** | **176** | `_meta.count = 176`、`added_count = 5`、`generator_version = 1.20.0` |
| 门 | 五道门 + 门⑥ 三段式 + `--check-completeness/--added/--generator-version` + `accept_m1` ×2 | **全部 exit 0** | §5 |

---

## 1. ① `check_rename_map.py` 的陈旧期望 → 派生

### 1.1 问题（**本批独立复现**，不引用 REPORT-067 的结论）

`docs/scripts/check_rename_map.py` 的 G 段把**契约的条数**与**字面量 171** 比：`:240` `check("G1 contract tool count == 171", len(ctools) == 171, ...)`，`:250` `check("G5 contract count == map total - 2 unregister - 1 merge", len(ctools) == 174 - 2 - 1, "%d == 171" % len(ctools))`。契约自 TASK-052/053/063 起是 `171 + N`（`_meta.added_count = 5` → **176**），所以这两行在任何当前树上都**恒 FAIL**，与「本批改了什么」无关。

本批的第一步就是**自己跑一遍**并落盘（不是引用 REPORT-067 §4.3）：

```
docs\scripts\check_rename_map.py  （改动前）
...
CONTRACT bytes=152873 sha256=d4e53b43840b6537af9dfbefdc77e7fb4ed6202ee23f3016503a7a53953e7ecd
[FAIL] G1 contract tool count == 171                              len=176
[PASS] G2 contract names unique                                   distinct=176
[PASS] G3 no unregistered/merged-source name leaks into the contract leaked=[]
[PASS] G4 both de-merged pairs present under 4 distinct names     present=[...4 names...]
[FAIL] G5 contract count == map total - 2 unregister - 1 merge    176 == 171

RESULT: FAIL (2 failing checks): G1 contract tool count == 171, G5 contract count == ...
exit code 1
```

判据：**恰好 2 条 FAIL，且两条都是「把 ported 半边的数当整条契约的数」**。

### 1.2 修法（`docs/scripts/check_rename_map.py`）

**形状**：`ported` 从**同一次运行的 `dropped` 集合**里数出来，`added` 从**契约自己的 `_meta`** 里读出来，契约大小是两者之和；**`171` 仍然是脚本里的字面量，而且仍然是被检查的对象**（G1），只是不再拿它去比整条契约的大小。

```python
# C 段（新增）：ported 半边从 disposition 拆分里数出来，而不是写下来
ported_count = len(kept_names)          # = 174 - 2 unregister - 1 merge，由数据算出

# G 段（新增的 FATAL 守卫 + 派生）
meta = contract.get("_meta", {})
added_tools = meta.get("added_tools", [])
if meta.get("added_count") != len(added_tools):
    sys.exit("FATAL: contract _meta.added_count %r != len(added_tools) %d" % (...))
if len(set(added_tools)) != len(added_tools):
    sys.exit("FATAL: contract _meta.added_tools has duplicates: %s" % sorted(added_tools))
added_count = len(added_tools)
expected_contract_count = ported_count + added_count
...
check("G1 ported half is still 171", ported_count == 171, "ported=%d" % ported_count)
...
check("G5 every _meta.added_tool is in the contract", not (set(added_tools) - set(cnames)), ...)
check("G6 contract count == map total - 2 unregister - 1 merge + _meta.added_count",
      len(ctools) == expected_contract_count,
      "%d == %d - 2 - 1 + %d = %d" % (len(ctools), rename_map.get("total"), added_count, expected_contract_count))
```

**为什么这样设计（逐条）**

1. **`ported_count` 不是新写下的数**：它是 `len(kept_names)` —— 同一段 C 段代码刚刚算出的「非 unregister、非 merge 的条目数」。也就是说它天然等于旧的 `174 - 2 - 1`，但**从数据里长出来**。任何一次 map 编辑（多一个 unregister、少一个 rename）都会让它跟着动，而**旧写法不会**。
2. **`171` 保留为被检查字面量**：G1 断言 `ported_count == 171`。**断言没有放松** —— 少了半个字面量就红；多了半个字面量也红（`ported_count` 会变）。任务书要求「171 保留为被检查的字面量」正是这一行的形状。
3. **`added` 的唯一权威是契约自己的 `_meta`**：`added_count` 与 `len(added_tools)` 在生成器里**故意冗余**（`gen_renamed_contract.py` 的注释：*a consumer that only needs the arithmetic does not have to trust a length*），所以脚本把两者比一遍，不一致就是 FATAL（在任何 G 检查之前）。
4. **多了一条 G5**（每个 added 名都在契约里）：派生只在大 `added_count` 自己诚实的前提下成立，所以「列表里的名字真的在契约里」必须单独断言。
5. **`174` 仍然出现**：G6 的**报错文本**里写着 `174 - 2 - 1`，因为那是 `rename_map.get("total")` 的真实来源；它不是被比较的期望值，只是让人一眼看出这个数是怎么来的。

### 1.3 修复前后退出码对照（**同一输入、同一进程、可复算**）

任务书要「修复前后的退出码对照」。改动前的树已经不存在，所以本批写了 `scripts\mcp068_exitcodes.ps1`：它把当前脚本的**两处 G 比较恢复成改动前的字面量**写进 `docs/scripts/check_rename_map_BEFORE_TASK068.py`（**仅在运行的这段时间**存在，`finally` 里删除，工作树零残留），分别跑两个版本：

```
[PASS] current_script_exits_0 :: exit=0 log=...\rename_map_after.txt
[PASS] pre_task068_script_exits_nonzero :: exit=1 log=...\rename_map_before.txt copy was ...\check_rename_map_BEFORE_TASK068.py (deleted)
[PASS] pre_task068_copy_is_deleted_from_the_tree :: ...\check_rename_map_BEFORE_TASK068.py
[PASS] pre_task068_script_fails_exactly_on_the_two_size_checks :: failing checks=2 [[FAIL] G1 contract tool count == 171                              len=176 | [FAIL] G5 contract count == map total - 2 unregister - 1 merge    176 == 171]
[PASS] current_script_has_no_failing_check :: failing checks=0
[PASS] reverse_probe_exits_0 :: exit=0 ...

BEFORE (pre-TASK-068 expressions, same input) = exit 1
AFTER  (current script)                       = exit 0
PROBE  (old false / new true, same input)     = exit 0
TASK-068 EXIT-CODE EVIDENCE PASS
```

即：**修复前 exit 1 且恰好那 2 条 FAIL；修复后 exit 0 且 0 条 FAIL**。两边的差异**只有那两处比较**（`cd /d <docs\scripts>` 运行，`__file__` 位置相同 → 读到的是同一批 JSON）。

> 本批在写这个 harness 时**连踩两个自己的错**，都留痕（因为「同输入」这件事必须真的成立）：
> ① 第一版把副本放在 `%TEMP%` → 脚本用 `os.path.dirname(__file__)` 找 `docs/*.json`，副本看不到 docs，报 `FileNotFoundError: ...\AppData\Local\Temp\tool-rename-map.json` —— 那次「before」不是被测试的行为在红；
> ② 第二版只替换 G6 的首行与期望行，把 `check(` 包裹留下 → 该调用变成嵌套表达式（仍能解析），于是**不打印、也不计入 FAILURES**，`failing checks=1`。改成**整块替换**（G6 五行 → G5 两行）后才是 2。
> 这两条已写进 `mcp068_exitcodes.ps1` 的注释：**「同输入对照」本身就是需要被验证的断言**。

### 1.4 反向探针（同输入下 **旧表达式为假 / 新表达式为真**）

`scripts\mcp068_rename_map_reverse_probe.ps1`（纯 ASCII，`Invoke-Expression` 在**真文件**上求值，7 条）：

```
[PASS] old_G1_contract_count_is_171                 ($ctoolCount -eq 171)                                   = False
[PASS] old_G5_contract_count_is_map_total_minus_2_minus_1 ($ctoolCount -eq (174 - 2 - 1))                    = False
[PASS] new_ported_half_is_still_171                 ($portedCount -eq 171)                                  = True
[PASS] new_contract_count_is_derived                ($ctoolCount -eq (($mapTotal - $unregisterCount - $mergeCount) + $addedCount)) = True
[PASS] new_added_count_matches_the_contract_list    (($addedCount -eq $addedTools.Count) -and ($addedCount -gt 0)) = True
[PASS] new_contract_count_is_not_vacuous            （同一表达式喂 added_count - 1）                        = False
[PASS] new_sixth_manifest_is_the_contract_added_list ($addedManifestNames.Count -eq $addedTools.Count)       = True
probes=7 failures=0
TASK-068 REVERSE PROBE PASS (...)
exit 0
```

**关键的两条**：`old_*` 在**同一输入**上为 **False**（这就是「旧表达式会红」的机器证据）；`new_contract_count_is_not_vacuous` 把同一个新表达式喂一个**被改坏的输入**（`_meta.added_count - 1`）后为 **False** —— 证明新断言不是恒真式。`new_ported_half_is_still_171` 证明**字面量 171 仍然在被检查**。

### 1.5 `scripts/**` 同类硬编码条数普查（任务书①「顺手普查」）

**工具**：`scripts\check_hardcoded_counts.py`（221 行，纯 ASCII 源码）。它对 `modules/mcp_server/scripts/**` 与 `modules/mcp_server/docs/scripts/**` 的 **144 个** `.ps1/.py/.cmd/.sh` 逐行扫任务书点名的 **7 个数**（`171/173/175/176/152/72/153`），把每一行分到 6 个桶之一，**任何无法归类的行都打印为 UNCLASSIFIED 并 exit 1**（这是脚本设计的目的：普查不能静默跳过看不懂的行）。脚本排除**它自己**（`SURVEY SKIPPED (self)`，因为它的数集与规则就写着这些数）。

```
SURVEY files scanned    = 144
SURVEY SKIPPED (self)   = scripts/check_hardcoded_counts.py
BUCKET DERIVED      = 53     <- 从 `_meta.added_count`/`portedCount`/算术里派生
BUCKET CHECKED      = 4      <- 保留为被检查的字面量（171 半边 / 174-2-1 派生式）
BUCKET PINNED       = 7      <- 拿字面量比**活产物**（这类**会**随契约增长过期）
BUCKET LIVE         = 3      <- 回显活端点的条数（153/72）的文本行
BUCKET FROZEN       = 80     <- 命名**过去某个 revision** 的数字，没有任何活比较读它
BUCKET UNCLASSIFIED = 0
BUCKET total        = 147
RESULT: PASS (every occurrence of 171/173/175/176/152/72/153 is classified; none is UNCLASSIFIED)
exit code 0
```

**逐条清单**：全部 147 行的 `文件:行 [数] 桶` 在 `evidence\task068\logs\census_hardcoded_counts_verbose.txt`（162 行，逐字）。下表是**需要决定**的几类，其余 133 行按定义不该动。

| 类别 | 位置（`文件:行`） | 那个数是什么 | 处理 | 理由 |
|---|---|---|---|---|
| **PINNED** | `scripts/mcp063_product_defects_evidence.ps1:374` | `Check 'contract_is_176_entries' ($contractNames.Count -eq 176)` | **本批不动，登记** | TASK-063 批次的取证脚本，**测的是它那一批的契约**（176 至今未变，现在仍绿）；它是「陈旧期望」的同类，**下一批若再增工具就会红**。改成派生需要改那个批次的证据脚本（超出本批范围） |
| **PINNED** | `scripts/mcp063_product_defects_evidence.ps1:468,482` | `$namesA.Count -eq 72` / `$namesB.Count -eq 153` | **本批不动，登记** | 活端点计数，随**任何**实现组增加而变 —— TASK-064 D-8 只修了「契约条数」那一半，**端点条数**这一半未覆盖（它属于 `accept_m1.ps1` 的职责面，而 `accept_m1` 已经派生） |
| **PINNED** | `scripts/mcp066b_run.ps1:349,730` | `$listACount -eq 153` / `$listGCount -eq 72` | **本批不动，登记** | TASK-066 B 角色的编排器（88 条判据），测那一批的活链；重跑它会重写已提交的 `evidence/task066b/**`（TASK-067 §4.3 已归因） |
| **CHECKED** | `docs/scripts/check_rename_map.py:302`（G1）、`scripts/gen_renamed_contract.py:26,2184`、`scripts/mcp068_rename_map_reverse_probe.ps1:80,105`、`scripts/mcp068_exitcodes.ps1`（对照文本） | `ported_count == 171` / `174 - 2 - 1 == 171` | **保留**（任务书要求的形状） | 这些行**故意**保留字面量：它们断言的是 **ported 半边**，不是整条契约。TASK-064 D-8 的四条修复（`accept_m1.ps1:207` 的 `171 + $ExpectedAddedCount`、`mcp052/053/054/059` 的 `$portedCount = 171` + `_meta.added_count`）也把 171 留在这个位置 |
| **LIVE** | `scripts/mcp063_product_defects_evidence.ps1:483`、`scripts/mcp064_stale_expectation_reverse_probe.ps1:95,117` | 回显文本里的 `153`/`152`/`72` | **不动** | 它们是**打印**（`-f $namesB.Count` 的格式串或 `-Expression`），数本身来自变量；`mcp064` 的两行**就是**「证明 152/72 这个字面量已经过期」的反向探针，**必须**保留旧值 |
| **FROZEN**（值得点名） | `scripts/mcp051_contract_diff.py:62` `EXPECTED_TOOLS = 171` | 断言「diff 的两侧都是 171 条」 | **本批不动，登记** | 该脚本要求**两个 revision 的契约文件作为参数**，且整体形状（`BEFORE_VERSION = "1.12.0"`、`AFTER_VERSION = "1.13.0"`、`BEFORE_OVERRIDES = 24`、`AFTER_OVERRIDES = 28`）是 **TASK-051 的 revision 对**；在**当前**契约上跑它没有意义（`mcp053_regression_battery.ps1:127` 逐字记录过）。**只改 171 会让这个脚本自相矛盾** |
| **FROZEN**（值得点名） | `scripts/mcp052_contract_diff.py:47` `EXPECTED_PORTS = 171`、`scripts/mcp053_contract_diff.py:49` `CONTRACT_PORTED_COUNT = 171`、`scripts/mcp059_contract_pre_post.py:62` `CONTRACT_PORTED_COUNT = 171` | ported 半边（**已经是** TASK-064 的派生形状） | **不动** | 这三个已经是「171 保留为 checked literal + 用 `_meta.added_count` 加回去」的形状 —— 本批 ① 的**同款修法**在 Python 侧的既有实现 |

**结论**：普查**没有发现第二处「该改而没改」的 hardcoded 条数**。`check_rename_map.py` 是唯一一处**把 171 直接当整条契约大小比**的地方；其余 146 行按定义分别是「派生」「故意保留的 checked literal」「取证脚本里的历史快照」「打印/探针」。三类 PINNED（`mcp063` ×3、`mcp066b` ×2）是**已知的、下一批会过期**的硬编码，逐条登记在 §6 的 next_step。

---

## 2. ② 两处描述澄清（契约 sha 只移动一次）

### 2.1 机制（走 `DESCRIPTION_OVERRIDES`，不手改契约）

两处都**追加**（`mode` 保持默认 `append`）：`value` = `<原描述逐字> + " " + <判别句>`，生成器的 append-only 守卫**逐字**检查原描述还在句首；`reason` 逐字引用被替换成员的相关原文/事实，并写进 `_meta.overrides` 以便审计。

`GENERATOR_VERSION` **1.19.0 → 1.20.0**（`scripts/gen_renamed_contract.py`），并同步 `docs/tool-groups-added.json` 的 `source.generator_version` 与 `source.entries`（三处必须同串，`--generator-version` 会断言，§5.5）。

**重生成**（逐字）：

```
gen_renamed_contract: input tools = 174
gen_renamed_contract: output tools = 176
gen_renamed_contract: added = 5 (project_build_csharp, project_write_text_file, project_validate_scripts, editor_set_node_script_batch, editor_set_node_property_updates)
gen_renamed_contract: overrides = 33 (… description/list_scripts:append, … description/run_test_scenario:append, …)
gen_renamed_contract: output sha256 = 701539829ed8fcaa227f280fb6bff71b96522248cd9c4b84f2073c27eb17cfe0
gen_renamed_contract: self-checks = OK (lint 176/176, unique 176/176, disposition enum OK)
```

`_meta.overrides` **31 → 33**（两条都是 `description`/`append`），`inputSchema` 一条未动，条数 **176 不变**。

**C++ 侧同步**：服务端读不到 `docs/`，`tools/list` 的字符串来自 C++ 字面量，所以两处描述必须在模块源码里同步，否则门①（逐字）会红：

* `tools/project_read_files.cpp` 的 `ToolBuilder("project_list_scripts", ...)` —— 手工同步（该文件不属生成段）；
* `tools/running_game_test_execution.cpp` 的生成段 —— 用**生成器**重跑：`python scripts/gen_b2_game_schema.py --group running_game_test_execution --in-place tools/running_game_test_execution.cpp`（它逐字复制契约条目；「再次运行是 no-op」由生成器自身保证）。

`scripts\mcp068_contract_cpp_diff.py` 在两棵文件上直接比对（**不经过树**）：

```
MATCH project_list_scripts          cpp bytes=373  contract bytes=373
MATCH running_game_run_test_scenario cpp bytes=571  contract bytes=571
RESULT: PASS (every checked tool's C++ description is the contract's description verbatim)
```

### 2.2 (i) `.godot` 生成脚本会被列出 —— **不收窄 walk**，如实声明

**裁决依据（D125 (b)）**：TASK-067 把「哪些文件算脚本」改成从 `ScriptServer` **派生**（构建有什么语言就列什么），而 **walk 本身一字未改**：`tools/project_read_files.cpp:215-239` 的 `_collect_scripts_recursive` 只跳过 `.` 与 `..`（`:228-230`），所以 `.godot`、`.hiddendir`、`addons` 都进。**收窄会撞钉住的断言**：`tests/test_mcp_server.h:2991` 的 `expected` 里有 `project.path(".hiddendir/secret.gd")`，那是**已发布证据的一部分**。且**列出生成文件是诚实的**：把「哪个目录是生成物」写进工具需要一个**新的、机器可验证的**判据，不能顺手塞进去。

**代价**（TASK-067 §1.4 已显式声明，但只有报告读者看得到）：真实 mono 工程的 `res://.godot/mono/temp/obj/**` 会被列出。本批的活证据实测 **2 条**：

```
p0_fixture_has_generated_cs_on_disk :: generated .cs under .godot = 2
  [res://.godot/mono/temp/obj/Debug/.NETCoreApp,Version=v8.0.AssemblyAttributes.cs,
   res://.godot/mono/temp/obj/Debug/McpBreakoutCs.AssemblyInfo.cs]
p3_generated_godot_cache_scripts_are_listed :: res://.godot/* = 2 [同上两条]
p3_generated_entries_are_under_the_mono_obj_path :: cache paths=同上
p3_hand_written_cs_listed :: res://scripts/*.cs listed=6 on disk=6
p3_hand_written_gd_listed :: res://scripts/*.gd listed=2 on disk=2
p3_count_is_the_array_size :: count=10 array=10
```

**修法（只改描述）**：`DESCRIPTION_OVERRIDES["list_scripts"]`，`mode=append`，新描述：

> 列出所有脚本文件 会包含 .godot 下的生成脚本：本工具的 walk 从 res:// 起递归，只跳过 . 与 ..，因此引擎自己生成的文件也在答案里（真实 mono 工程会出现 res://.godot/mono/temp/obj/** 下的 .cs，例如 res://.godot/mono/temp/obj/Debug/*.AssemblyInfo.cs），调用方若要只看手写脚本请自行过滤这些路径。

`reason` 逐字记录了：被替换成员的原文（`列出所有脚本文件`）、`_collect_scripts_recursive` 只跳 `.`/`..`、`.hiddendir/secret.gd` 那条断言是「不得按点前缀收窄」的理由、REPORT-067 §1.4 的 2 条实测、以及裁决（不收窄 = D125 裁决 (b)）。

**「旧调用仍可用」的证据**：参数面**零变化** —— 活证据 `p1_list_scripts_schema_still_has_no_argument :: properties=`（契约的 `inputSchema` 仍是空对象）；同一进程的既有行为不变（`count=10`、`res://scripts/*.cs=6`、`*.gd=2`，与 TASK-067 的 POST 结果逐条相同）。

### 2.3 (ii) `waited_seconds` 入/出参命名 —— **先核实事实**，结果**不是同名异义**，只改描述

**任务书要求先核实事实并给 `文件:行` 与两种读法的线上证据。核实结果（三条事实，逐条给出处）：**

| # | 事实 | 依据 |
|---|---|---|
| **F1** | **入参**（`wait` 步骤的等待时长）在契约里叫 **`seconds`**，而且是 `steps[].properties` 里**唯一**一个等待时长成员 | `docs/tools_list.renamed.json` 的 `running_game_run_test_scenario.inputSchema.properties.steps.items.properties`：`action, expected, keycode, node_path, operator, pressed, property, **seconds**, strength, text, type`（线上证据：`p2_waited_seconds_is_not_an_input :: step properties=action,expected,keycode,node_path,operator,pressed,property,seconds,strength,text,type`） |
| **F2** | 实现**只读** `seconds`，完全不认识入参里的 `waited_seconds` | `tools/running_game_test_execution.cpp:316` `if (_step_has_key(step, "seconds"))`、`:317` `optional_float(step, "seconds", 0.0, parsed.wait_seconds, ...)`；`:337` 的拒绝文案 `" is a 'wait' step but carries neither 'seconds' nor 'node_path'"`（**只提 `seconds`**） |
| **F3** | **结果**里每个 `wait` 条目回显 `waited_seconds`；它镜像的是**请求侧**的值，而且**取决于哪种 wait**：按时间等待镜像 `seconds`（`:440`），按 `node_path` 等待**超时**时镜像 `timeout`（`:459`）；**找到节点时不回显**（`:461-465`） | `tools/running_game_test_execution.cpp:440` `entry["waited_seconds"] = step.wait_seconds;`、`:459` `entry["waited_seconds"] = step.wait_timeout_seconds;` |

**结论**：**不是「同一个名字既做入参又做出参」**。入参成员是 `seconds`（`step` 对象里），出参成员是 `waited_seconds`（`result` 条目里）—— **两个不同的成员、两个不同的对象**。按任务书②的情形 ②「只是文档含混」处理：**只改描述**。

**为什么不改名、也不加别名（逐条）**

1. **改名会破坏既有调用方**：契约的输入面是唯一权威，`seconds` 是既有线上证据（`evidence\task066\...\g4_wait_hit_and_assert_score__0016__*.request.json` 写的就是 `{"type":"wait","seconds":1.2}`）与 TASK-019 以来所有调用者用的名字。
2. **加一个入参别名 `waited_seconds` 会把线上 schema 扩出契约**：门① 是 `tools/list` 与契约的**逐字**比对；契约的 `inputSchema` 没有这个成员，加它就不是「澄清」而是**未声明的功能变更**（与 TASK-068 的授权范围不符）。
3. **「旧调用仍可用」的证据**（本批实测，四条）：
   * **成功路径**：`p2_wait_seconds_call_is_not_an_error :: code=0`、`p2_wait_seconds_step_completed :: wait entry={"step":0,"type":"wait","waited_seconds":1.5}`、`p2_echo_is_the_requested_seconds :: requested=1.5 echo=1.5` —— 正是既有调用方的形状（请求 `seconds`，回显 `waited_seconds`）。
   * **参数校验没变**：`p2_bad_seconds_is_still_refused :: code=-32602 message=Parameter 'seconds' must be a number, got String`。
   * **把 `waited_seconds` 当入参仍被拒绝**：`p2_legacy_name_request_is_recorded :: code=-32602 message=Parameter 'steps[0]' is a 'wait' step but carries neither 'seconds' nor 'node_path'` —— 「`waited_seconds` 不是入参」在线上**被实测为真**。
   * **两种 wait 的差别也实测**：`p2_found_node_wait_answers_found_without_echo :: entry={"found":true,"node_path":"/root/Main","step":0,"type":"wait"}`（找到节点 → 无回显）与 `p2_timeout_branch_echo_mirrors_timeout :: requested timeout=0.25 found=False echo=0.25 entry={"found":false,...,"waited_seconds":0.25}`（超时 → 回显 timeout）。
4. **clause 必须把 `timeout` 那半边也写上**：如果描述只说「`waited_seconds` 是等到的秒数」，对 `node_path` 形式就是**错的**（它回显 `timeout`）。所以判别句写「按时间等待的步骤回显的就是 seconds；按 node_path 等待的步骤回显 timeout」，并给出 `:440` 与 `:459`。

**新描述**（`DESCRIPTION_OVERRIDES["run_test_scenario"]`，`mode=append`）：

> 运行测试场景并执行一系列测试步骤 wait 步骤的入参名是 seconds（steps[i].seconds，契约 schema 里唯一的等待时长成员），结果里每个 wait 条目的回显字段叫 waited_seconds（按时间等待的步骤回显的就是 seconds；按 node_path 等待的步骤回显 timeout，见 tools/running_game_test_execution.cpp:440 与:459）；两者在**不同的对象**里，waited_seconds 不是入参（把它写进请求的 step 不生效，seconds 才是入参），入参名与结果字段名都未改动、既有调用不受影响。

**线上逐字**（两个端点各自算）：

```
p1b_project_list_scripts_live_description_equals_contract_editor_9888 :: live bytes=205 contract bytes=205 equal=True
p1b_project_list_scripts_live_description_equals_contract_game_9889   :: live bytes=205 contract bytes=205 equal=True
p1b_running_game_run_test_scenario_live_description_equals_contract_game_9889 :: live bytes=301 contract bytes=301 equal=True
p2_run_test_scenario_is_registered_on_the_game_endpoint :: game tools=72
p2_run_scenario_description_keeps_the_original_head :: head preserved=True
```

（`running_game_run_test_scenario` 的 `scope = game`，所以 9888 上没有它 —— `p1_run_test_scenario_is_absent_from_the_editor_endpoint` **PASS**。本批第一版 harness 写错过这一点：它在编辑器列表里找该工具，得到的当然是空串。）

### 2.4 门① 逐字（两端口、本组 6 条）

`scripts\check_contract_subset.ps1 -Group project_read_files`（最终 plain 二进制；exit **0**，逐字节见 `evidence\task068\logs\gate1_contract_subset_project_read_files.log`）：

```
[PASS] editor_9888_contract_subset   editor port=9888 tools=153
   | project_list_scripts: name=True description=True inputSchema=True
   | project_read_script: name=True description=True inputSchema=True
   | project_validate_script: name=True description=True inputSchema=True
   | project_read_resource: name=True description=True inputSchema=True
   | project_get_resource_preview: name=True description=True inputSchema=True
   | project_read_scene_file_content: name=True description=True inputSchema=True
[PASS] game_9889_contract_subset     game port=9889 tools=72   （同样 6 条全 True）
[PASS] guard_user_port_9877          pid_before=-1 pid_after=-1
group=project_read_files tools=6 contract=176
3/3 checks passed
```

---

## 3. TDD：红 → 绿

### 3.1 红相位（**改动前实现 + 新测试**，输出当场落盘）

新测试 `[MCPServer] TASK-068 the two clarified descriptions are registered`（`tests/test_mcp_server.h`，在「消息内容的**活**值」上断言，不是断言契约文件）：

```
.\modules/mcp_server/tests/test_mcp_server.h(3247): ERROR: CHECK( list_scripts.begins_with(String::utf8("列出所有脚本文件 ")) ) is NOT correct!
  values: CHECK( false )
.(3250) CHECK( list_scripts.contains(String::utf8(".godot")) )          values: CHECK( false )
.(3251) CHECK( list_scripts.contains(String::utf8("生成脚本")) )          values: CHECK( false )
.(3252) CHECK( list_scripts.contains("res://.godot/mono/temp/obj/**") ) values: CHECK( false )
.(3253) CHECK( list_scripts.contains(String::utf8("自行过滤")) )          values: CHECK( false )
.(3260) CHECK( run_scenario.begins_with(String::utf8("运行测试场景并执行一系列测试步骤 ")) ) values: CHECK( false )
.(3263) CHECK( run_scenario.contains("seconds") )                       values: CHECK( false )
.(3264) CHECK( run_scenario.contains("waited_seconds") )                values: CHECK( false )
.(3265) CHECK( run_scenario.contains(String::utf8("不同的对象")) )        values: CHECK( false )
.(3266) CHECK( run_scenario.contains(String::utf8("不是入参")) )          values: CHECK( false )
.(3267) CHECK( run_scenario.contains("steps[i].seconds") )              values: CHECK( false )
.(3272) CHECK( run_scenario.contains("tools/running_game_test_execution.cpp:440") ) values: CHECK( false )
.(3273) CHECK( run_scenario.contains(":459") )                          values: CHECK( false )
.(3274) CHECK( run_scenario.contains("timeout") )                       values: CHECK( false )
[doctest] test cases:  1 | 0 passed |  1 failed | 1773 skipped
[doctest] assertions: 18 | 4 passed | 14 failed |
[doctest] Status: FAILURE!
```

红相位是**真的红**：14 条失败全部指向**行为缺口**（描述的活值），4 条通过的是**负向断言**（`step_properties` 里没有 `waited_seconds`、`has("seconds")`、editor 端点没有该工具）—— 它们本来就该在红相位就绿，因为本批**没有**改那两件事。做法：把两个 C++ 文件的改动先 `git checkout HEAD --` 掉（同时**保存副本**），构建，跑，再**还原**（`git status` 确认两个文件回到 ` M`）。

### 3.2 绿相位

```
--test-case=[MCPServer] TASK-068*
[doctest] test cases:  1 |  1 passed | 0 failed | 1773 skipped
[doctest] assertions: 18 | 18 passed | 0 failed |
[doctest] Status: SUCCESS!
```

### 3.3 测试为什么这样写（两条诚实说明）

1. **断言「活值」而不是契约文件**：服务端读不到 `docs/`，客户端真收到的字符串是 C++ 里的 `String::utf8(...)`。门① 管「活值 == 契约」，这个 doctest 管「新描述的两个子句还在」—— 契约漏了、C++ 忘了同步、或**后来有人把子句删掉**，都会被这个用例挡住。
2. **两个负向断言也在这个用例里**（`CHECK_FALSE(step_properties.has("waited_seconds"))`、`CHECK(description_of(editor_list, ...).is_empty())`）：它们把「没有加别名」和「scope 没变」变成**可执行**的事实，而不是报告里的一句话。

### 3.4 门③/④（模块 + 全引擎）

```
gate3: --headless --test --test-case="[MCPServer]*"
  test cases:  345 |  345 passed | 0 failed | 1429 skipped
  assertions: 23971 | 23971 passed | 0 failed
  Status: SUCCESS!            exit 0

gate4: --headless --test
  test cases:  1771 | 1771 passed | 0 failed | 3 skipped
  assertions: 448218 | 448218 passed | 0 failed
  Status: SUCCESS!            exit 0
```

**与上一份 HEAD 锚定的基线对比**（`REPORT-067`：门③ 344/23953、门④ 1770/448200）：门③ **+1 用例 / +18 断言**（正是本批新增的用例），门④ **+1 用例 / +18 断言**，**没有减少、没有变红**。

---

## 4. ③ 报告勘误（append-only）

### 4.1 做法

`docs/reports/BREAKOUT-FINDINGS-R4.md` **末尾追加「附录 A」**（+48 行），**不改** §8.3 原文一个字节（`git diff` 逐字：`48 ++++`，全部在文档末尾）。

### 4.2 勘误内容（要点）

| 项 | 值 |
|---|---|
| 被勘误对象 | §8.3 正文（第 507 行）引用的 `19968 B` |
| 追加的实测（TASK-068，2026-09-25） | `C:\Users\wyl\AppData\Local\Temp\mcp-breakout-cs\proj\.godot\mono\temp\bin\Debug\McpBreakoutCs.dll` = **20992 B**，sha256 **`2e1ff3ddaee79f6826e41919057278ba5a4c3a4c1739365602a2dd6550676320`** |
| 谁在哪个提交上实测 | TASK-068 实现工程师，工作树 `git rev-parse HEAD` = **`eff591a14`**（构建**之前**、模块源码**改动前**的时刻） |
| 测量方式 | `(Get-Item <path>).Length` + `Get-FileHash -Algorithm SHA256`，由 `mcp068_live.ps1` 在**任何 MCP 调用之前**跑，产物 = `evidence\task068\run-mono-head\mono-head_p0_breakout_dll__0001__*.summary.json` |
| 与 R4 自身的关系 | R4 §8.3 自己的 **20992 / `2e1ff3dd…`** 本轮**独立复算成功**（不是引用 R4 的结论）—— 问题只在**引文里那个 19968** |

### 4.3 **为什么不改原文**（三条，已逐字写进附录 A）

1. **19968 是「A 的原叙述」的逐字引用**：改动被引用的数字会让读者无法再核对 `REPORT-066:39` 到底写了什么，勘误本身失去可验证性。
2. **`REPORT-066` 是已发布的历史报告**：按 PLAYBOOK §7.3 与 TASK-067 §3 的口径，历史报告走**追加勘误**不回填 —— R4 §8.3 自己就是这样处理 `REPORT-066` 的，附录 A 只是把 R4 的同一纪律**应用到 R4 自己身上**。
3. **两个数字同时在场才有信息量**：`19968`（session 1）→ `20992`（session 2 修 `CsVerdict.cs` 后）正是「同一工程两次构建、程序集变大」这条时间线的**唯一可读形式**。

附录 A 还写了**诚实边界**：`20992` 的正确读法是「TASK-068 实测时刻、该工程盘上的值」（任何一次重新 `dotnet build` 都会产生新程序集），与 §8.3 对 `19968` 的读法同构。

---

## 5. 门、纪律与机器检查

### 5.1 构建与版本锚定（严格串行，从 cmd，输出不经管道）

| 步骤 | 命令 | 日志 | 退出码 |
|---|---|---|---|
| 0（任务书要求的第 0 步，改动前的树） | `modules\mcp_server\scripts\build_local.cmd -Force`（plain，`tests=yes`） | `%TEMP%\mcp068_build_plain_step0.log` | **0**（12:57:31 → 12:58:22） |
| 红相位 plain（C++ 描述已临时还原 + 新测试） | 同上 | `%TEMP%\mcp068_build_plain_red.log` | **0** |
| 绿相位 plain | `build_local.cmd -Force` | `%TEMP%\mcp068_build_plain_green.log` | **0** |
| 绿相位 mono | `modules\mcp_server\scripts\mcp057_build_mono.cmd` | `%TEMP%\mcp068_build_mono_green.log` | **0** |

```
bin\godot.windows.editor.x86_64.console.exe      --version -> 4.8.dev.custom_build.eff591a14
bin\godot.windows.editor.x86_64.mono.console.exe --version -> 4.8.dev.mono.custom_build.eff591a14
git rev-parse --short=9 HEAD                                -> eff591a14        (both == HEAD)
```

**⚠️ 本批自己踩到并修正的一条（重要，留痕）**：第一次跑活证据用的是**陈旧 mono 二进制**（`4.8.dev.mono.custom_build.716957c26` —— 只重建了 plain），于是 `p1_list_scripts_description_*` 全红、`project_list_scripts` 只回 8 字节的旧描述。**根因是流程**：mono 与 plain 都要建（任务书 §4 明写「mono 与 plain 都需时」），第一次只跑了 plain。重建 mono 后两个二进制都 `== eff591a14`，活证据全绿（45/45）。**那条失败的运行没有入库**（证据树在重建后从零重跑），这条留痕是为了让下一个读者不要把「mono 没重建」误读成模块缺陷。

### 5.2 门①（逐字）

见 §2.4。`exit 0`；`-Group project_read_files`；9888 = 153 tools / 9889 = 72 tools / `contract=176`；本组 6 条 `name/description/inputSchema` 全 `True`；`guard_user_port_9877 pid_before=-1 pid_after=-1`。

### 5.3 门②（三类证据 + 跨工具端到端活链）

`project_list_scripts`（TASK-068 描述澄清的对象）：

| 类别 | 可构造 | 证据 |
|---|---|---|
| 成功 | **可** | `p3_list_scripts_call_is_not_an_error :: code=0`、`p3_count_is_the_array_size :: count=10 array=10`、`p3_hand_written_cs_listed :: 6 == 6`、`p3_hand_written_gd_listed :: 2 == 2`，请求/响应字节落盘（`run-mono-head\calls\mono-head_p3_list_scripts__*.{request,response}.json`，名字里带 sha8） |
| **缺参 → `-32602`** | **不可构造（显式声明）** | 契约 `project_list_scripts.inputSchema = {"properties":{},"required":[],"type":"object"}` —— **没有参数**，结构上不存在「缺参」这一类（活证据 `properties=`）。 |
| **底层失败** | **不可构造（显式声明）** | 该工具按设计没有自己的错误类：walk 根恒为 `res://`，读不了的目录**静默跳过**（`tools/project_read_files.cpp:218-220` 的注释逐字写着 `this tool has no error of its own, not even for res://`）。要构造只能造一个 `res://` 不可读的进程，本 harness 做不到，且做了也不改变任何判据。 |
| **跨工具端到端活链** | **可** | `project_list_scripts{}`（列出）→ 取 `res://scripts/Main.cs`（或任一 `.gd`）→ `project_read_script` 读回 → `project_get_filesystem_tree{path:"res://scripts"}` 独立确认。本批的链是 **3 个工具对同一个文件的三次观察同时成立**（TASK-067 §1.1 已有同型链，本批用同一 fixture 的副本）。 |

`running_game_run_test_scenario`（第二处描述澄清）：成功（`p2_wait_seconds_call_is_not_an_error :: code=0` + 回显 `waited_seconds=1.5`）、**错参 → `-32602`**（`p2_bad_seconds_is_still_refused`、`p2_legacy_name_request_is_recorded`）、**底层失败**（节点不存在 → `found:false` 而不是错误，`p2_timeout_branch_echo_mirrors_timeout`）、跨工具链（`wait`/`found`/`assert` 三种步骤的回显形状互相对照；更宽的 `editor_simulate_input_*` ↔ `running_game_*` 链在 TASK-044/066 的证据树里，本批不重复）。

### 5.4 门⑤（`accept_m1` ×2 + 15 步回归电池）

**门⑤ 本体（`accept_m1.ps1` 连跑两次，PASS 清单必须一致）**

```
=== accept_m1_run1 ===  exit=0 :: PASS  gate_scope_declared | 22/22 cases passed | implemented tools = 153 (editor endpoint) / 72 (game endpoint); contract = 176; known_deviation = per-batch verbatim gate only
=== accept_m1_run2 ===  exit=0 :: PASS  gate_scope_declared | 22/22 cases passed | implemented tools = 153 (editor endpoint) / 72 (game endpoint); contract = 176; known_deviation = per-batch verbatim gate only
accept_m1_pass_lists_agree|0|accept_m1_run1 checks=22 accept_m1_run2 checks=22 differing_lines=0
```

**两次 PASS 清单逐行相同（`differing_lines=0`）**、22/22 用例、`contract = 176`。

**电池逐步退出码（`summary.txt` 逐字，共 18 步）**

```
accept_m1_run1 | 0            accept_m1_run2 | 0
mcp041_gates | 0              mcp042_gates | 0              mcp043_gates | 0
mcp010_b2_observation_evidence | 0
mcp019_b4_evidence | 0        mcp027_object_shape_and_paths_evidence | 0
mcp044_capture_evidence | 0   mcp045_pixel_compare_cost | 0  mcp046_capture_encode_cost | 0
mcp050_parameter_guidance_evidence | 0   mcp051_b_tier_evidence | 0
mcp052_added_tools_evidence | 0          mcp053_added_tools_evidence | 0
accept_m1_pass_lists_agree | 0           tracked_evidence_restored | 1
```

**16/18 步 exit 0**；唯一非零步是电池自己的「跑完之后工作树必须干净」断言，**与 TASK-067 的同一现象同因**：它要求 `git diff --stat` 为空，而任何「工作树里带着本批未提交改动」的批次都不可能满足。电池自己的 manifest：

```
KEPT-DIRTY-BEFORE-THE-RUN modules/mcp_server/docs/reports/BREAKOUT-FINDINGS-R4.md
KEPT-DIRTY-BEFORE-THE-RUN modules/mcp_server/docs/scripts/check_rename_map.py
KEPT-DIRTY-BEFORE-THE-RUN modules/mcp_server/docs/tool-groups-added.json
KEPT-DIRTY-BEFORE-THE-RUN modules/mcp_server/docs/tools_list.renamed.json
KEPT-DIRTY-BEFORE-THE-RUN modules/mcp_server/scripts/gen_renamed_contract.py
KEPT-DIRTY-BEFORE-THE-RUN modules/mcp_server/tests/test_mcp_server.h
KEPT-DIRTY-BEFORE-THE-RUN modules/mcp_server/tools/project_read_files.cpp
KEPT-DIRTY-BEFORE-THE-RUN modules/mcp_server/tools/running_game_test_execution.cpp
SUMMARY restored=57 removed=2 kept-dirty-before=8
tracked_evidence_restored|1|git diff --stat after=9 line(s); newly modified=0; newly untracked=0; restore failures=0
```

即：`newly modified=0 / newly untracked=0 / restore failures=0` —— **电池没有「修改」任何本批源码**（8 条全部是「电池开始前就脏的」）。

**⚠️ 电池删掉过本报告，本批重建（必须留痕）**：`tracked_evidence_restored` 这一步的语义是「把电池**见过的**新增/修改路径还原掉」，而本报告当时已经在树里（电池启动前的 `git status` 就列着它），于是被它当作「本批的临时产物」删除。**同类风险**：任何在电池运行之前写下的**未跟踪**产物都会被删。本批已逐一核对：证据树 `evidence/task068/` 与 9 个新脚本都还在，**被删的只有这份报告**（已重建，内容与初次版本一致，并新增了本段留痕）。**结论：报告应在电池之后写，或接受一次重建。**

**各步内部计数（脚本自报）**：`mcp010` 29/29、`mcp027` 60/60、`mcp044` 40/40、`mcp045` 15/15、`mcp046` 23/23、`mcp052` **53/53**、`mcp053` **73/73**；`mcp041/042/043_gates` 各自把 gates 3/4/6 + gate 1 + gate 5 ×2 + 自己的证据链 + 5 个回归 + `probe037` + `mcp040_*` 跑完并各自 exit 0（末步 `STEP regress_mcp040_racing EXIT 0 (44-48s)`）。

**⚠️ 逐条归因：`mcp041/042/043_gates` 的 `exit 0` 是驱动脚本的退出码，不是每一步的（本批新发现，必须留痕）**

`mcp042_gates.ps1:29-39` 的 `Invoke-Step` **只把每一步的退出码写进 summary**，函数本身不检查它；驱动脚本最后没有「有任何一步非零就 exit 1」的收口。因此电池的 `mcp042_gates|0` **不代表**它内部的每一步都 0。本批**逐个读了每一步的日志**，发现 **3 个步骤内红**（全部**与本批改动面无关**）：

| 步骤 | 内部结果 | 失败的检查 | 归因（谁让它红的） |
|---|---|---|---|
| `mcp042_gates` → `gate2_rewrite_and_honesty_evidence` | `30 checks, 3 failed` | `A22_every_hand_written_comment_is_gone`（实测 `comments lost 0/4; kept 4`）、`A23_the_engine_writes_its_own_header_instead`、`A26b_the_only_lost_lines_are_the_comments`（`0 original line(s) no longer present`） | **TASK-057 补丁 2 / TASK-059 的行为切换**：`editor_add_input_action` 的持久化改走 `save_custom_section()`，注释**不再丢**。TASK-042 的这三条断言把「整文件重写 ⇒ 注释全丢」写死了（`REPORT-042 §4` 逐字写着 `comments lost 4/4; kept 0`），于是**行为改善**反而让它们红。**本批没有改 `editor_add_input_action`、也没有改 `tool_helpers.*`**（§5.6 的 8 个 ` M ` 里没有它们） |
| `mcp043_gates` → `gate2a_description_evidence` | `16 checks, 5 failed` | `L21_project_set_setting_ends_with_the_appended_sentence`、`L21_project_add_autoload_…`、`L21_project_remove_autoload_…`、`L21_editor_add_input_action_…`、`L21_editor_reload_plugin_…` | **TASK-059 D-4** 把这五条描述从 `append` 改成 `replace`（`DESCRIPTION_OVERRIDES`），TASK-043 的 `L21` 断的是「描述以追加句结尾」。**本批没有碰这五条描述**（本批新增的是 `list_scripts` 与 `run_test_scenario` 两条，都不在这些名字里） |
| `mcp043_gates` → `gate2d_rewrite_evidence` | `30 checks, 3 failed` | 与上表第一行**同一批 A22/A23/A26b** | 同上（TASK-043 的脚本是 TASK-042 那份的副本） |

**这三条为什么不是本批的回归，证据是什么**

1. **改动面不相交**：本批的 8 个文件（§5.6）与 `editor_add_input_action` 的持久化路径（`modules/mcp_server/tools/editor_input_simulation.cpp`、`tool_helpers.cpp`）、以及那五条描述（`project_set_setting` / `add_autoload` / `remove_autoload` / `set_input_action` / `reload_plugin`）**都没有交集**。`git status` 逐字可查。
2. **失败的方向是「行为变好」**：`A22` 期望「注释全丢」，实测「4/4 全在」；`L21` 期望「以追加句结尾」，实测是 TASK-059 的 `replace` 文本。两边的失败都指向**更早的批次已经换了行为/文本**。
3. **本批自己的同因见证**：本批在同一棵树上跑 `mcp068_live.ps1`，`project.godot` 的注释保全与 TASK-067 §2.3 的结论一致（本批没重跑 §2 的注释活链，因为它不是本批的对象；`p3_list_scripts` 与 `p1b` 的描述比对才是）。
4. **诚实边界**：本批**没有**重建「TASK-057 之前」的二进制去实测这三条的反向对照（那需要另一次完整 mono 构建 + 一整套活链）。因此本表给出的是**归因（含源码与报告出处）**，不是「在同一棵树上用旧行为重放」的直接证据。**这条限制不得读成「已独立复现」。**

**未跑脚本的逐条归因**（`mcp041..mcp067` 里的其余项）

| 脚本 | 为什么不在本批重跑 |
|---|---|
| `mcp057_gates.ps1` / `mcp055_gates.ps1` / `mcp056_gates.ps1` | 三者的步骤清单是 `mcp059_gates.ps1` 的真子集（同样 gates 3/4/6 + `check_tool_groups.py` 机器检查 + `gate1_contract_subset`）。本批**改为直接跑并集里与本批相关的机器检查**（§5.5 三条 + `check_rename_map.py` + 门① + 门③④⑥），而不是整条重跑 —— `mcp059_gates.ps1` 会写 `evidence/task059/**`，与 ①②③ 的改动面（描述文本、脚本派生）不相交 |
| `mcp054_gate_battery.ps1` / `mcp051_gates.ps1` | 其中 `mcp051_gates.ps1` 特有的两个 python 检查本批**单独跑了**：`check_tool_groups.py`（**PASS**）与 `check_rename_map.py`（**本批已修 → exit 0**）；`mcp051_contract_diff.py` 是 TASK-051 的 revision 对快照（§1.5），在**当前**契约上跑没有意义（`mcp053_regression_battery.ps1:127` 逐字记录过） |
| `mcp050/051/053/054_regression_battery.ps1` | 四条是**更早批次**的回归电池（`accept_m1` ×2 + 它们那一轮的证据脚本 + `mcp031_gate6_coverage_probes.ps1`）。本批跑的是**同一个形状的最新一条**（`mcp056_regression_battery.ps1`，TASK-057 §3 重写过、带工作树快照/还原/manifest） |
| `mcp041_gates.ps1` / `mcp042_gates.ps1` / `mcp043_gates.ps1` | **已在电池里跑过**（上表逐步退出码 + 内部归因） |
| `mcp010/019/027/044/045/046/050/051/052/053_*` | **已在电池里跑过**（同上） |
| `mcp043_contract_diff.py` / `mcp043_group_lookup.py` / `mcp043_registration_literals.py` | **已在 `mcp043_gates` 里跑过**（`gate2g/gate2h/gate2i` 全 EXIT 0） |
| `mcp067_live.ps1` | **未重跑**：它是 TASK-067 的 pre/post 对照（`-Phase pre` 需要一棵「改动前」的树与一个未修二进制）；本批不是它的对象，且 `mcp068_live.ps1` 已在同型 fixture 上覆盖了 `.godot` 生成脚本与描述逐字两件事 |
| `mcp065b_run.ps1` / `mcp066b_run.ps1` 与其余取证脚本 | 会**重写已提交的** `evidence/task065b/**`（358 文件）/ `evidence/task066b/**`，主题（捕获、像素、scope）与 ①②③ 不相交（与 TASK-067 §4.3 的归因同款） |

### 5.5 门⑥ 三段式 + 三个契约机器检查

**门⑥ 三段式（全部 exit 0）**

```
gate6_narrowing            exit=0   scanned: 75  pinned: 75
                                    note: 18 pinned line number(s) drifted (既有；pin 按 marker id+occurrence 判定，非失败)
                                    PASS: every narrowing point ... annotated and pinned
gate6_narrowing_coverage   exit=0   17 declared spellings + boundary printed
gate6_coverage_probes      exit=0   101/101 checks passed
                                    (log sha256=f98554f04873c59adb62ebb1a4a937b9533419443a0ddb3ca85c2b2b2bfdd976)
```

* **`scanned == pinned == 75`、0 误报** —— 与 TASK-067 的 75/75 相同。本批**没有新增收窄点**：`project_read_files.cpp` 只多了一段注释与一个更长的字符串字面量；`running_game_test_execution.cpp` 的改动在生成段内的 `ToolBuilder(...)` 描述串里。
* **18 条 line drift 是既有的**，且 drift 列表里的文件**没有一个**是本批改的（`editor_animation_tree_write.cpp` / `editor_input_simulation.cpp` / `editor_write_scene_editor.cpp` / `project_theme_write.cpp` / `project_write_resource_scene.cpp` / `tool_helpers.cpp`）。
* **§22.3b 规则 4（不拿门⑥ 变绿当唯一证据）**：本批的收窄证据是**三条腿** —— 机器检查（上表）+ **代码审查**（本批新增收窄写法 = **0**；唯一涉及长度的是描述字符串的 `String::utf8`）+ **行为证据**（§2.2/§2.3 的活证据 + §3 的 18 断言）。**「新增收窄点 × 经过的闸门 × 证据」= 无，因为新增点为 0。**

**三个契约机器检查（任务书点名必须 exit 0）**

```