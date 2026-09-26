# REPORT-071 — A：采纳守卫的**文件级清单**；B：修 **F-1** 测试配置独立性 + 门③ 口径

- **任务书**：`docs/tasks/TASK-071-guard-inventory-and-test-config.md`
- **来源**：`docs/reports/REPORT-070-audit-unconfirmed-closure.md` §⑤（守卫盲区 + 原型 + 成本）与 §④/§5.4（F-1）
- **契约**：**176**（条数不变；门① 实况 `contract=176`，编辑器 **153** / 游戏 **72**，并集 **176**）
- **构建锚点（D86 ①）**：`4512d14c7e` —— 两个二进制自报 `4.8.dev.custom_build.4512d14c7` / `4.8.dev.double.custom_build.4512d14c7`，与当时的 `git rev-parse --short HEAD` **逐字一致**。门①–⑥ 全部在该锚点上采集。
- **交付提交**：`4c2532c178`。`4512d14c7e..4c2532c178` 只动 `modules/mcp_server/**`：`docs/**` 19 个、`scripts/**` 5 个、`tests/test_mcp_server.h` 1 个（**唯一**的编译输入）。该文件在跑门时**已经是**工作树里的这一版，所以二进制的代码 == 提交记录的代码，**只有**烘焙进版本串的 HEAD 前缀不同（R-1，见 §D.6）。**未 push**。
- **9877**：全程 `pid=-1`（无监听），本批**从未请求**该端口（门② `G230` 的 `asked_by_us=False`）。

---

## 0. 结论一览

| 项 | 结论 | 关键证据（锚点 `4512d14c7e`） |
|---|---|---|
| **A 盲区 A**（快照前已存在、之后被别处删除的未跟踪文件） | **已消除沉默**：现在**点名** | TASK-070 第一版：**0 行**提到它；本批：`UNTOUCHED-MISSING-UNTRACKED …mcp070-blindspot-victim-a.txt`（1 行），且 `RESTORED*` 行 **0** 条（`probe_mcp070_second_edition.txt`，10/10 PASS） |
| **A 盲区 B**（已存在未跟踪目录**内部**的改写与新建） | **已消除沉默**：现在**点名** | 现在：新建文件 2 行（`APPEARED-UNTRACKED` + `UNTOUCHED`）、被改写文件 1 行（`UNTOUCHED-CHANGED-UNTRACKED`） |
| **A 电池裁决** | **不再瞎**：`MISSING/CHANGED` 计入 declared-leftover | 同一场景把植入根**声明**后，declared-leftover 由 0 → **4**（含 victim A）；`g_battery_verdict_now_counts_a_missing_untracked_file` |
| **A 能力边界（必须说清）** | **只能发现，不能还原** | `MISSING`/`CHANGED` 的字节不在 git 里；取消后文件**仍然不在**、被改写文件**仍是新字节**（`W11`/`W13`、`g_blindspot_a/b_is_detected_but_NOT_restored`） |
| **A 成本** | 默认模式 **约 2.3 s/次**（4026 个未跟踪文件）；`-HashUntracked` **约 6.6 s/次** | `W40`：2 336 ms / 6 587 ms；TASK-070 §⑤ 记录 2 304 ms / 6 445 ms —— **复测一致**（D86 ②） |
| **A 不留痕** | `git status --porcelain -uall` **逐字节不变** | `W50`：before=4029 行 sha256 `35a1f59031ff`，after 同；`mcp070` `g_repository_left_exactly_as_it_started` 同 |
| **B 红相位（改前，双精度）** | **当场保存** | `345 \| 338 passed \| 7 failed`；`23961 \| 23862 passed \| 99 failed`；失败断言里 **FLOAT32 = 0 条**、`REAL_T` = 22 处文本（`doctest_module_double_RED.txt`） |
| **B 单精度（绿）** | 用例数与断言数与 TASK-070 基线**一致** | `345/345 passed`，`23971/23971` assertions（TASK-070 §6.1：345 / 23971） |
| **B 双精度（绿）** | **345 全过** | `345/345 passed`，`23956/23956` assertions（`doctest_module_double_GREEN.txt`） |
| **门③ 口径** | **门③（`[MCPServer]*`）是单精度门；双精度当前未被任何门覆盖（未纳入门）** | 见 §B.4 |

---

## A. 守卫改为**文件级清单**

### A.1 改了什么（源码）

| 文件 | sha256 | 改动 |
|---|---|---|
| `scripts/mcp_evidence_guard.ps1` | `0fb4e51d131334312f9d76d3d63eb9d91043e502948f8205daa3616bb778e1d5` | `Get-McpEvidenceState` 改读 `git status --porcelain -uall`，新增 **`UntrackedInventory`**（`path -> 'length:LastWriteTimeUtc.Ticks'`，`-HashUntracked` 时追加 `:sha256`）与 `UntrackedInventoryHashed`；新增 `Get-McpUntrackedInventory` / `Compare-McpUntrackedInventory`；`Restore-McpEvidence` 新增三类清单行 + `-HashUntracked` |
| `scripts/mcp056_regression_battery.ps1` | `a4733df38464b20e99a2fe6f3cc2f9b7afbae3372729ae2c88b5f5dd283037c6` | 电池裁决把 `MISSING`/`CHANGED` 计入 declared-leftover；裁决行扩字段 |
| `scripts/mcp070_guard_blindspot_probe.ps1` | `1d915eb471f685a810e35a27c2ecec6aca6dab874b5dd6385e19e3ccf66d6d8f` | **第二版**：同两个场景，断言从「看不见」反转为「**必须被点名**」 |
| `scripts/mcp071_guard_inventory_probe.ps1` | `a3b3c46c136f0d4ac7fca0e99f31f3d60713b4f9c96a02b0603e36061837cd73` | 新增：三类语义、声明/未声明、可发现≠可还原、`-HashUntracked` 增益、成本、porcelain 逐字节不变（**17/17 PASS**） |
| `scripts/mcp071_gate2_live_evidence.ps1` | `a0b4f026f2dfc5926564e6d128af501eb60f91d965f809725be2a88a467bc5bd` | 新增：门② 的活证据采集器（14/14 PASS） |

**清单行语义**（任务书允许命名微调，三种语义都在）：

```
MISSING-UNTRACKED  <p>             声明过的、快照前在、现在没了 —— 【发现，不可还原】
CHANGED-UNTRACKED  <p>             声明过的、长度/mtime(/sha256) 变了 —— 【发现，不可还原】
APPEARED-UNTRACKED <p>             现在的多了 —— 【发现，可还原（删除）】
UNTOUCHED-MISSING-UNTRACKED <p>    同上三类中【未声明】的那些：只报告，绝不动
UNTOUCHED-CHANGED-UNTRACKED <p>
UNTOUCHED <p>                      （出现在 BEFORE 之后的新未跟踪文件）
PRUNED-EMPTY-DIR <p>               文件级删除后【声明且为空】的目录（新，见 A.4）
RESTORE-FAILED <p>                 现在也覆盖「声明了却删不掉」的那一半
SUMMARY ... missing-untracked=... changed-untracked=... appeared-untracked=... pruned-dirs=... inventory-hashed=...
```

`SUMMARY` **向后兼容**：`restored=` / `removed=` / `kept-dirty-before=` / `untouched=` 四个旧字段逐字保留，只在尾部追加新字段——因此 TASK-069 的白名单探针（`mcp069_guard_whitelist_probe.ps1`，W16 断言 `untouched=2`、W23 断言 `untouched=3`）**未改一行仍然 13/13 PASS**。

### A.2 判定跟上（任务书 A.3）

电池（`mcp056`）不再只看「新出现的 modified/untracked」，而是把**文件级 diff** 的三类并进候选集：

```
$leftoverCandidates = newModified + newUntracked + Missing + Changed      # TASK-071 A
$declaredLeftover   = 候选集 ∩ 声明集合      # 非 0 即 tracked_evidence_restored=1（失败）
$undeclaredLeftover = 候选集 \ 声明集合      # 只报告
```

因此「快照前已存在、之后被别处删除」的文件**再也不可能**被报成 `tracked_evidence_restored`。现场证据：`g_battery_verdict_now_counts_a_missing_untracked_file` —— 同一场景下 declared-leftover 由第一版的 **0** 变成 **4**（含 victim A），而本批真实电池跑出来是 `missing=0 changed=0 appeared=4 declared leftovers=0`（因为你没有真的删东西；**发现通道的增益只在真删除时改变裁决**）。

> 顺带钉住一个新的诚实性缺口：`RESTORE-FAILED` 现在也覆盖「声明了却删不掉的 appeared 文件」，所以 `APPEARED` 那一半的失败不会再被 `restored=` 的计数掩盖。

### A.3 证据 ①：重跑 TASK-070 §⑤ 的两个盲区场景（**现在必须被点名**）

`mcp070_guard_blindspot_probe.ps1` **第二版**，10/10 PASS，exit 0（`probe_mcp070_second_edition.txt`；证据根 `%TEMP%\mcp070\guard\20260925-174754\`）。第一版的实测值写在脚本头部与下面的对照里（append-only，D86 ③）：

| 场景 | 第一版（锚点 `3cbaacd6b`） | **本批（锚点 `4512d14c7e`）** |
|---|---|---|
| 对照：新未跟踪文件（**看得见**） | `UNTOUCHED <p>` | `APPEARED-UNTRACKED <p>` + `UNTOUCHED <p>` |
| 盲区 A：快照前已存在、之后被删 | **0 行**；`SUMMARY` 一字不提；文件仍然不在 | **1 行**：`UNTOUCHED-MISSING-UNTRACKED …victim-a.txt`；`RESTORED*` 称它被还原 = **0 行**；文件**仍然不在** |
| 盲区 B：未跟踪目录内改写 + 新建 | **0 行** | 新建：`APPEARED-UNTRACKED …new-after-snapshot.txt` + `UNTOUCHED …`（2 行）；改写：`UNTOUCHED-CHANGED-UNTRACKED …victim.txt`（1 行） |
| 电池裁决机制 | declared-leftover = 0（=「证据已还原」） | 同一场景**声明后** declared-leftover = **4**（含 victim A） |
| `git status --porcelain -uall` | 4026 行，diff 0 | 4030 行，diff **0**，前后 sha256 相同 |

**为什么第一版的两条断言被反转、而不是删掉**：第一版断言的是「守卫看不见」，它测的是**旧实现**，本批改动使这个断言不再成立。按 PLAYBOOK §7.3「证据被证伪时要撤回、append-only 勘误」，本报告在此**显式声明**：第一版的三条检查 id（`g_guard_does_see_a_new_untracked_file` / `g_blindspot_a_…_is_invisible` / `g_blindspot_b_…_are_invisible`）在本批被重命名为 `g_…_is_now_named` 并反转判据，第一版的真实输出仍被 REPORT-070 §5 与脚本头部逐字保留。

### A.4 证据 ②：成本实测（不哈希 / 哈希）

`mcp071_guard_inventory_probe.ps1`（17/17 PASS，exit 0；`probe_mcp071.txt`，证据根 `%TEMP%\mcp071\guard-inventory\`）：

| 模式 | 本仓 **4026** 个未跟踪文件 | REPORT-070 §⑤ | 抓得到 |
|---|---|---|---|
| 默认（`-uall` + 每文件一次 `Get-Item`，**不读内容**） | **2 336 ms**（整次 `Get-McpEvidenceState` 2 399 ms） | 2 304 ms | 删除、新建、长度/mtime 变化的改写 |
| `-HashUntracked`（每文件 sha256） | **6 587 ms**（整次 6 654 ms） | 6 445 ms | 外加「**等长且同 tick**」的改写 |

`-HashUntracked` **默认关**的理由（任务书要求写进报告）：① 默认模式已经把「删除」这一整类变成可见，而删除才是会伪造 PASS 的那一类；② 默认模式**不读文件内容**，成本与文件量线性而常数极小（2.3 s / 一次几十分钟的电池）；③ 需要内容级保证时才付 ~2.8× 的代价。增益被实测钉住：`W17` 用 `[IO.File]::SetLastWriteTimeUtc` 把改写后的 mtime **复位到原值**，默认模式确实**看不到**（0 行），`W20` 在 `-HashUntracked` 下**点名** `CHANGED-UNTRACKED`。

### A.5 证据 ③：**只能发现，不能还原**（明确声明）

- 已删除的未跟踪文件：git 里没有它的字节 —— `MISSING-UNTRACKED` 只是**把静默换成点名**。`W11`／`g_blindspot_a_is_detected_but_NOT_restored`：restore 之后文件**仍然不存在**。
- 已改写的未跟踪文件：旧字节同样没有留底 —— `CHANGED-UNTRACKED` 同理。`W13`／`g_blindspot_b_is_detected_but_NOT_restored`：文件**仍是改写后的字节**。
- 唯一**可还原**的是 `APPEARED-UNTRACKED`（删除），且**仅当路径被声明**；未声明的路径一律 `UNTOUCHED`（TASK-069 的默认拒绝不变，`W30`）。
- 报告与探针的输出文本里一律用 `named` / `detected`，**没有**任何一处把这三类说成 restored。

### A.6 证据 ④：不留痕

`git status --porcelain -uall` 的**全文 sha256 前后相同**，不只是行数相同：
- `mcp071` `W50`：before=4029 行 sha256 `35a1f59031ff…`，after 同，differing=0；
- `mcp070` `g_repository_left_exactly_as_it_started`：before=4030 行 sha256 `140748599e2a…`，after 同，differing=0；
- 门② `G231`：before=4037 行 sha256 `ceaacf63cdcc…`，after 同，differing=0。

### A.7 本批**额外**加固的两处（不是任务书要求，逐条声明）

1. **哈希模式对「读不到的文件」不再中止整个守卫**：另一个进程（本批实测：我自己用来落盘探针输出的 `Tee-Object` 目标）持有文件时 `Get-FileHash` 会抛错，而 `$ErrorActionPreference='Stop'` 会让整个守卫崩掉。现在记为 `length:mtime:unreadable`；两次快照都读不到即视为无变化（保守答案）。**这是实测出来的**，不是假设。
2. **快照与还原的哈希模式必须一致**：`-HashUntracked` 与快照时不一致时**抛错**，而不是把每个文件都报成 `CHANGED`（两种 identity 字符串不可比）。

### A.8 A 的边界（与 TASK-070 §⑤ 一致，不夸大）

- 它是**探测**不是**还原**（A.5）。
- 它**只看得见 `git status` 看得见的东西**：`.gitignore` 覆盖的路径（`bin/`、`.godot/`、**`*.log`**）在这套机制之外。**本批实测到的一次现场**：电池自己的 15 份步骤 `.log` 全部被 `.gitignore` 的 `*.log` 忽略，所以 `appeared-untracked=4`（3 个非 log 文件 + 1 个声明的新文件）而不是 ~22 —— 这不是缺陷，是这套机制的**已知边界**的现场证明。
- 默认模式会被「**等长且同 tick**」改写骗过（`W17` 实测），要内容级保证需开 `-HashUntracked`。

---

## B. F-1：测试的配置独立性

### B.1 红相位（**改前**，双精度，当场保存）

- 二进制：`bin\godot.windows.editor.double.x86_64.console.exe`，自报 `4.8.dev.double.custom_build.4512d14c7`（= 当时的 HEAD）。构建 `build_double_red.log`：**START 17:41:37 → END 17:42:28，exit 0**。
- 命令：`--headless --test --test-case="[MCPServer]*"` → `doctest_module_double_RED.txt`，sha256 `7f8d2d2d1140d70a6e5518723a30fb5888083f85ca9566f23be23d4cf5e1d371`。
- 结果：**`345 用例 \| 338 passed \| 7 failed`；`23961 断言 \| 23862 passed \| 99 failed`**（与 REPORT-070 §5.4 逐字一致 —— D86 ② 复测确认，不是陈旧结论）。

**红的 7 条（逐字，与任务书列的 7 条完全对应）**：

1. `TASK-022 D-4: a scalar real_t member refuses a value that does not survive the slot`
2. `TASK-022: one gate decides the width of every narrowing slot`
3. `TASK-022 D-4: the batch paths refuse a scalar real_t overflow before any write`
4. `TASK-025 E-3 (write half): a rect component outside its slot is refused by the existing gate`
5. `TASK-028 G-1: a sub-property path writes one component through the same gate`
6. `TASK-028 G-1: Vector4 components, nested objects and Dictionary members`
7. `TASK-033 the Quaternion read and write shapes are closed`

**99 条失败断言的分布**（按源码行）：14443–14445 ×6、14471/14472/14478/14479/14480 ×6、14474 ×5、14756–14759 ×3、14765–14767 ×2、14810 ×1、14824 ×1、14825 ×1、14856–14862 ×1、14877–14879 ×1、16098–16101 ×1、16630/16631 ×1、16632 ×3、16645 ×1、16756–16758 ×1、17795–17797 ×1。
**失败断言里点名 `FLOAT32` 的 = 0 条**；`REAL_T` 文本出现 22 处 —— 与任务书给的「单精度期望、off-class = 0」一致。

### B.2 采用的写法与**理由**（任务书要求判断哪种更贴命题）

**选择：`if (sizeof(real_t) == 4)`，单精度分支逐字保留原断言，64 位分支断言「`real_t` 槽**应当接受**」，并在该分支**追加一条 `ValueSlot::FLOAT32` 的拒绝断言**。**

理由（第一性原理）：这 7 条用例的**命题**是「**同一个闸门按槽位宽度判定**」（它们的标题与注释自己这么写：「one gate decides the width of every narrowing slot」）。`1e300` 是否被拒**从来不是命题本身**，而是「槽位宽度」在这个构建里的**取值**：

- 单精度构建下宽度 = 32 位 → 拒绝（原断言，逐字保留）；
- `precision=double` 下 `real_t` **就是** 64 位 → 拒绝它反而是**错的**，正确的等价断言是「接受，而且是那个值」。

所以「改成接受」不是放宽断言，而是**把断言与它引用的槽位对齐**；真正需要在不依赖构建的前提下被覆盖的「32 位收窄」命题，改用 `FLOAT32` 槽（`Color` 分量 / `PackedFloat32Array` 元素）——那正是 D-15 的设计（`tool_helpers.cpp:1801-1807` 的 `FLOAT32` 那一半无条件编译）。因此每个 64 位分支**都补了 FLOAT32 拒绝**，使「收窄必须被拒」这条命题在**两种构建下都存在**，而 `1e300` 那条变成构建相关。

> 为什么**没有**把 7 条整体改指向 `FLOAT32` 槽：那会把「标量 `real_t` 成员 / `Vector2`/`Rect2`/`Vector4`/`Quaternion` 分量」这些**真实存在的写路径**从测试里删掉（它们仍然必须按自己的槽宽判定），等于用「换一个槽」掩盖「同一个槽在另一个构建里的正确答案」。

### B.3 绿相位与计数

| 构建 | 用例 | 断言 | 命令与证据 |
|---|---|---|---|
| **单精度**（`4512d14c7e`，`build_local.cmd -Force`，START 17:50:22 → END 17:52:07，exit 0） | **345 \| 345 passed \| 0 failed** | **23971 \| 23971 passed \| 0 failed** | `doctest_module_single_GREEN.txt` sha256 `52e926a6a563781f031c140b03caf031effb5909ac2352587a79123b1e2ab55c` |
| **双精度**（`4512d14c7e`，`mcp070_build_double.cmd`，START 17:53:58 → END 17:54:51，exit 0） | **345 \| 345 passed \| 0 failed** | **23956 \| 23956 passed \| 0 failed** | `doctest_module_double_GREEN.txt` sha256 `fb24b0e67e0368f2c4b67774be46d375f7047eff577ef2741778c68dc8cb4966` |
| 门④ 全引擎回归（单精度） | **1771 \| 1771 passed \| 0 failed \| 3 skipped** | **448218 \| 448218 passed \| 0 failed** | `doctest_full_engine.txt` sha256 `98295391f6f934c13c7cc7c7c42f023dd5eabb8af173317e9bdc636253f5ebdb`（= TASK-070 §6.1 基线） |

- **单精度 `345/23971` 与 TASK-070 基线逐字一致，未减少**（任务书 B.2①）。实现方式：所有新增断言都在 `else`（64 位）分支里，单精度分支**逐字保留**原代码；第 5 条（`position:y`）的唯一结构性调整是把循环里的 `1e300` 拆出来单独判定，单精度下断言条数 **9 → 9**（6 + 3），未变。
- **双精度 `345/345`**（任务书 B.2②，不需要「为何仍小于」的解释）。
- 断言数双精度比单精度**少 15**：这是 `if/else` 两条分支的**固有**差异（本批之前差 10，见 REPORT-070 §5.4），不是删除断言——**用例数 345 两边相同**。
- 三个构建的 START/END **互不重叠**（17:41:37–17:42:28 / 17:50:22–17:52:07 / 17:53:58–17:54:51），全程**只有一个 scons**（D62）。

### B.4 门③ 的口径（任务书 B.3 要求明确写下）

- **门③（`--test --test-case="[MCPServer]*"`，PLAYBOOK §3 第③行）是单精度门。** 它跑的是 `bin\godot.windows.editor.x86_64.console.exe`，即 `precision` 缺省（`float`）的构建。基线 `345 / 23971` 是**单精度**的数字。
- **双精度当前没有**被任何门覆盖：门①②④⑤⑥ 全部是单精度/脚本级门；没有任何门会构建或运行 `bin\godot.windows.editor.double.x86_64.console.exe`。**结论：双精度「未纳入门」**——本批的双精度 `345/345` 是**手工构建 + 手工跑**得到的证据（已写入本报告与 `evidence/task071/`），**不是**门③ 的一部分。
- 建议（给决策者）：把 `precision=double` 作为门③ 的**可选变体**（构建 ~1 分钟增量、冷构建 14m51s，命令已固化在 `scripts/mcp070_build_double.cmd`）。本批修完 F-1 之后，该变体在**本机实测 345/345**，具备了进门的前提。

---

## C. 门与纪律

### C.1 五道门 + 门⑥ 三段式

| 门 | 命令 | 结果（锚点 `4512d14c7e`） |
|---|---|---|
| ① 契约子集逐字 | `scripts\check_contract_subset.ps1` | **3/3 PASS**，exit 0；`contract=176`；`implemented_union = 153 (editor) / 72 (game)`；编辑器 9888 与游戏 9889 各 6 条 `name`/`description`/`inputSchema` 逐字 True；`guard_user_port_9877 pid_before=-1 pid_after=-1`（`gate1_contract_subset.txt`） |
| ② 三类证据（活） | `scripts\mcp071_gate2_live_evidence.ps1` | **14/14 PASS**，exit 0（`gate2_live_evidence.txt`）。见 C.2 |
| ③ 模块 doctest（单精度） | `--headless --test --test-case="[MCPServer]*"` | **345 passed / 0 failed / 1429 skipped**，**23971 assertions / 0 failed** |
| ④ 全引擎回归 | `--headless --test` | **1771 passed / 0 failed / 3 skipped**，**448218 assertions / 0 failed** |
| ⑤ `accept_m1` ×2 | `scripts\mcp056_regression_battery.ps1`（步骤 1/2 + 清单比较） | **两次都 23/23**；`accept_m1_pass_lists_agree\|0\|differing_lines=0` |
| ⑥ 收窄点清单（三段式） | ① `python scripts\check_narrowing_points.py` | **exit 0**：`scanned=75 pinned=75`，0 误报（`17 declared spelling(s)`）。18 条**行号漂移**提示是**既有**的（全部在 `tools/**`，本批一行未动 `tools/**`），脚本自身声明「不是失败」 |
| | ② `python scripts\check_narrowing_points.py --coverage` | **exit 0**；打印 17 种已声明拼写与集合外部分（`gate6_coverage.txt`） |
| | ③ `scripts\mcp031_gate6_coverage_probes.ps1` | **exit 0**：**101/101 checks passed**（含 `B1b_restored_scanned_75`、`B1b_restored_byte_identical`、`B5_false_positive_guard_stays_green`）；探针后**逐字节还原** |

- `python docs\scripts\check_tool_groups.py --check-completeness` → **exit 0**（`TOOL-GROUPS-COMPLETENESS CHECK PASS`，`BYTES ADDED 8072`，`SHA256 ADDED 0295cf86…`）
- `... --added` → **exit 0**（`TOOL-GROUPS-ADDED CHECK PASS`，同一 sha256）
- `... --generator-version` → **exit 0**（`GENERATOR-VERSION CHECK PASS (1.20.0)`）
- 契约条数 **176 不变**（三个模式都断言这一点）。

### C.2 门②（本批的「三类证据」是什么，为什么这样定义）

本批**没有新增/修改任何工具**，所以门② 不能是「每个新工具的成功/缺参/底层失败」。本批的门② 是**活端点的三类请求 + 一条跨工具链**（这是 PLAYBOOK §3 第②行在「非工具批次」上的对应物），逐条真实请求–响应（`curl.exe -s -o` 落盘 + sha256）：

| 检查 | 证据 |
|---|---|
| `G203/G204` 编辑器 `tools/list` | bytes=61863 sha256 `333b4a6858aa…`；实况 **153** 个工具 |
| `G206/G207` 游戏 `tools/list` | bytes=32973 sha256 `0ed732aff616…`；实况 **72** 个工具 |
| `G208` | **并集 = 176 = 契约 176**；missing=0；extra=0 |
| `G210` **成功类** | `project_get_info` bytes=194 sha256 `d4605a025573…`；`{"editor_screen_size":…,"project_name":"MCP071 gate 2 live evidence",…}` |
| `G211` **缺参类** | `project_read_script` 缺 `path` → `-32602`；`Missing required parameter: path`；bytes=212 sha256 `fb75536f5dc8…` |
| `G212` **底层失败类** | `project_read_script` 读不存在的路径 → `-32001` + `data.suggestion="Use project_get_filesystem_tree to list the files of the project"`；bytes=197 sha256 `4ff2407c6778…` |
| `G220` **跨工具链** | `project_create_script` → `project_read_script`（读到 marker）→ `project_validate_script`（`valid`）；盘上 54 字节 |
| `G230/G231` | 9877 `pid_before=-1 pid_after=-1 asked_by_us=False`；`porcelain -uall` 前后同 sha256 |

### C.3 回归相关脚本**逐条归因**（任务书硬性要求）

回归电池（`mcp056_regression_battery.ps1`，本仓 22 个文件、15 步）**整脚本重跑**，证据根 `docs/reports/evidence/task071/battery/`（`summary.txt`、`restore_manifest.txt`、`accept_m1_pass_list_compare.txt`、前后 `git_status_short_*`/`git_diff_stat_*`）+ `battery_stdout.txt`：

| # | 步骤 | exit | 归因 |
|---|---|---|---|
| 1–2 | `accept_m1_run1/2` | 0 / 0 | 23/23 ×2；port 9877 无监听；契约 176；153/72 |
| — | `accept_m1_pass_lists_agree` | **0** | `checks=23/23 differing_lines=0`（门⑤ 的判据） |
| 3–5 | `mcp041_gates` / `mcp042_gates` / `mcp043_gates` | 0 / 0 / 0 | `ALL STEPS EXIT 0`（17/19/29 步）。它们打印的 `tree dirty after the run:` 是**记录**不是判据（REPORT-070 §4.2 已判定），本批的脏树是 TASK-071 自己的 4 个已改文件 + 未跟踪产物 |
| 6–11 | `mcp010` / `mcp019` / `mcp027` / `mcp044` / `mcp045` / `mcp046` | 0 ×6 | 29/29、H1 9877 guard PASS、60/60、40/40、15/15、23/23 |
| 12–13 | `mcp050` / `mcp051` | 0 / 0 | 9877 guard pass；`task050/red/summary.json` sha256 `7ca74c27…`、`task051/red/summary.json` sha256 `4451e58d…` |
| 14 | `mcp052_added_tools_evidence` | **1** | **不是 TASK-071 回归**：唯一失败检查 `engines_match_head`——`plain --version='4.8.dev.custom_build.4512d14c7'`（= HEAD，正确）；`mono --version='4.8.dev.mono.custom_build.3cbaacd6b'`（**陈旧**）；`git HEAD='4512d14c7'`。**锚点归因**：`3cbaacd6b` 是 TASK-070 的构建锚点；`3cbaacd6b..HEAD` 的唯一提交 `4512d14c7e` 只增 `docs/` 与 `scripts/mcp070_*`（**0 行 C++**），mono 二进制 mtime `16:40:36` 早于该提交。REPORT-070 §4.2 的表里这两步在锚点 `3cbaacd6b` 上是 `53/53` / `73/73`（含 `engines_match_head`）——即**漂移由 TASK-070 的提交产生，与本批无关** |
| 15 | `mcp053_added_tools_evidence` | **1** | 同上（`72/73`，同一 `engines_match_head`）。两处失败**逐条同一原因**，没有第二类失败 |
| — | `tracked_evidence_restored` | **0** | `declared leftovers=0 (every declared artifact is back); undeclared paths left alone=4; restore failures=0; git diff --stat after=5 line(s); file-level untracked detection: appeared=4 missing=0 changed=0 (missing/changed are DETECTED, never restored; a declared one fails this verdict - TASK-071 A)` |

**还原清单的现场**（`restore_manifest.txt`，70 行）：`RESTORED` **57** 条已跟踪证据（task050/051/053 三根下，逐字节回到 HEAD）+ `RESTORED-NEW` **1** 条（`task051/red/e20_child_status.json`，全批唯一步骤新建的文件）+ `KEPT-DIRTY-BEFORE-THE-RUN` **4** 条（本批 4 个已改已跟踪文件，**不是**电池动过它们）+ `SUMMARY restored=57 removed=1 kept-dirty-before=4 untouched=3 missing-untracked=0 changed-untracked=0 appeared-untracked=4 pruned-dirs=0 inventory-hashed=false`。
- **`restored=57` vs REPORT-070 的 56**：多出的 1 条是本次步骤真正重写的已跟踪证据文件（同一根下同一机制），**不是**行为变化；两次都满足 `declared leftovers=0`。
- 被 `UNTOUCHED` 的 3 条是**未声明**的：本报告所在目录里的 3 个非 log 文件（`git_status_short_before.txt`、`git_diff_stat_before.txt`、`accept_m1_pass_list_compare.txt`）——TASK-069「按声明还原、声明外只报告不动」的又一次现场复现；另 15 份步骤 `.log` 被 `.gitignore` 的 `*.log` 忽略（见 A.8）。
- **电池进程退出码 = 1**（`FAILED STEPS: 2`），原因**只有**上面第 14/15 步的陈旧 mono 锚点。
- **本批没有重建 mono**：任务书的构建清单只有单精度与双精度两个变体，重建 mono 属于范围外；而且 TASK-071 的改动**不可能**影响 mono 的 version 字符串（本批未动任何 C++ 编译输入）。**建议**下一步用 `scripts\mcp057_build_mono.cmd` 重建 mono 并重跑这 2 步（~15 min），以把锚点推回 HEAD。

### C.4 其它反向探针（未改一行，仍绿）

- `scripts\mcp069_guard_whitelist_probe.ps1`：**13/13 PASS，exit 0** —— 默认拒绝、声明区分、`SUMMARY untouched=2/3` 全部照旧（本批的 `SUMMARY` 向后兼容由此**实测**背书）。
- `scripts\mcp070_guard_blindspot_probe.ps1`（第二版）：**10/10 PASS，exit 0**。
- `scripts\mcp071_guard_inventory_probe.ps1`：**17/17 PASS，exit 0**。

### C.5 纪律清单

| 要求 | 状态 |
|---|---|
| 只改 `modules/mcp_server/**`；hof-rs 只读 | ✅ 本批改动全部在 `modules/mcp_server/{scripts,tests,docs/reports/evidence/task071}`；hof-rs 未写 |
| 不改 `DESIGN-DETAIL`（要改先报） | ✅ 未改（门③ 的「单精度门」口径**只写在本报告**，见 §B.4，供决策者决定是否入规范） |
| 绝不占用/杀/重启 9877 | ✅ 三个采集器都断言 `pid_before == pid_after == -1`、`asked_by_us=False` |
| 端口 9888/9889 | ✅ 全程只用这两个 |
| 禁止 push | ✅ 未 push |
| 构建严格串行、从 cmd 启动、不抑制输出 | ✅ 三次构建 START/END 互不重叠；全部 `MCP_BUILD_LOG` 落盘 + 控制台输出 |
| 证据 `curl.exe -s -o` + sha256 | ✅ 门② 的 12 份响应全部落盘并给 sha256 |
| `.ps1` 纯 ASCII | ✅ `mcp_evidence_guard.ps1` / `mcp056_regression_battery.ps1` / `mcp070_guard_blindspot_probe.ps1` / `mcp071_guard_inventory_probe.ps1` / `mcp071_gate2_live_evidence.ps1` 非 ASCII 字节数全为 **0** |
| 红相位输出当场保存 | ✅ `doctest_module_double_RED.txt`（sha256 `7f8d2d2d…`） |
| 门⑥ 三段式 + §22.3b 规则 4 | ✅ 三段全 exit 0；本批 `tools/**` **零改动**，无新增收窄点 |
| `--check-completeness/--added/--generator-version` exit 0 | ✅ 三个都 exit 0 |
| `accept_m1` ×2 清单一致 | ✅ `differing_lines=0` |
| 结论按 D86 标锚点 | ✅ 全文结论均标 `4512d14c7e`；REPORT-070 的两处引用（F-1 的 338/7、§⑤ 的 2 304/6 445 ms）**在本批复测一致** |
| 产物一律绝对路径 | ✅ 报告与证据均为绝对路径 |

---

## D. deviations / risks / blockers / next step

### D.1 deviations（与任务书/手册的偏离，逐条显式）

1. **`mcp070_guard_blindspot_probe.ps1` 被就地改为第二版**（判据反转 + 3 个检查 id 重命名）。理由与 append-only 勘误见 §A.3。第一版的所有实测值仍保留在脚本头部与 REPORT-070 §5。
2. **门② 的定义**：本批无新工具，按「活端点三类请求 + 跨工具链」采集（§C.2），与 PLAYBOOK §3「每个新工具三类」在**形式上不同**、在**证据强度**上等价（都是真实请求-响应 + sha256）。
3. **新增 `PRUNED-EMPTY-DIR` 与 `UNTOUCHED-MISSING/CHANGED-UNTRACKED` 两类行**（任务书只点名了三种语义；命名微调已获任务书许可，且未声明的两类是保持 TASK-069 默认拒绝语义所必需）。
4. **`-HashUntracked` 默认关**（任务书允许），理由与成本见 §A.4；另加了两处未要求的加固（§A.7）。
5. **未重建 mono**，因此电池整脚本 **exit 1**（`FAILED STEPS: 2`）。归因见 §C.3；这是本批**唯一**的非零，且**不是** TASK-071 引入的。
6. **二进制锚点与交付提交相差一个提交**：门全部在 `4512d14c7e`（当时 `--version == HEAD` 为真）采集，交付提交 `4c2532c178` 在其后。逐字核对：`git diff --name-only 4512d14c7e..4c2532c178` = `modules/mcp_server/docs/**` 19 + `modules/mcp_server/scripts/**` 5 + `modules/mcp_server/tests/test_mcp_server.h` 1；**引擎与模块的其它 C++ 一行未动**，而唯一的编译输入 `tests/test_mcp_server.h` 在跑门时**已经是**这一版（本批先改测试、再 `build_local.cmd -Force`），因此**二进制的内容 == 提交记录的内容**，差异**只在**烘焙的版本串。严格按 PLAYBOOK R-1，**下一次跑门之前仍必须重建**（届时 `--version` 会自报 `4c2532c178`）。
7. **双精度断言数 23956 ≠ 单精度 23971**（依据见 §B.3）：`if/else` 分支的固有差异，用例数相同（345）。
8. **`restored=57` vs REPORT-070 的 `restored=56`**（§C.3）：同一机制，多 1 个被步骤重写的已跟踪证据文件。

### D.2 本报告的两个已知限制（诚实声明）

1. **`MISSING`/`CHANGED` 的「能发现」不等于「能还原」**：本批把「静默」换成了「点名」，**没有**新增任何恢复能力；如果一次删除发生在**未声明**的路径上，裁决不会失败（`W30` 实测），只会被打印。
2. **本次场景是构造的**（`%TEMP%` + 本仓内植入后清理），**不是**一次真实的第三方删除事故；它证明的是**通道**在真删除时会点亮，以及电池裁决会因此变成非零（`g_battery_verdict_now_counts_a_missing_untracked_file`：0 → 4）。

### D.3 blockers

**无。** 本批没有阻塞项。

### D.4 next step（给决策者）

1. **把「门③ 是单精度门、双精度未纳入门」写进规范**（决策者才有权改 `DESIGN-DETAIL`），并决定是否把 `precision=double` 加为门③ 的**可选变体**（本机现已实测 345/345，具备前提）。
2. **重建 mono**（`scripts\mcp057_build_mono.cmd`）并重跑 `mcp052`/`mcp053`，把 `engines_match_head` 的锚点推回 HEAD——这是 TASK-070 的提交留下的漂移，不是本批的。
3. 下一次跑门时**先重建单精度**（`build_local.cmd -Force`），使 `--version == 4c2532c178`（R-1）。
4. 若要内容级保证，把某个**只针对 `mcp_server/**` 子树**的 `-HashUntracked` 变体做成可选步骤（本批已给出成本与增益的实测）。