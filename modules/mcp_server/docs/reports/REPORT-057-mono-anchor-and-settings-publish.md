# REPORT-057 — 收口三条（D-B1 / R-B2 / R-B3）+ 引擎补丁 2：`project.godot` 局部发布

> **本报告由 TASK-058 恢复并补跑。** TASK-057 的**实现已提交**（`96f631addb`），但执行者写完代码即中断，
> `docs/reports/REPORT-057-*.md` **缺失**。TASK-058 的职责是：只读核实该提交到底改了什么、**补跑缺的项**、
> 如实列出 TASK-057 未完成/做错的地方并做完、然后写下这份报告。
>
> **报告路径说明（缺陷 D-6，见 §6）**：TASK-057 任务书标题写的是
> `REPORT-057-mono-anchor-and-project-settings-publish.md`，但其正文第 4 行写
> `REPORT-057-mono-anchor-and-settings-publish.md`；TASK-058 的 §1.4 明确要求后者。
> 本报告采用 **TASK-058 指定的路径**（`…-settings-publish.md`），TASK-057 任务书自身的路径不一致已列为缺陷。

- **status**：PASS（D-B1 / R-B2 / R-B3 / 引擎补丁 2 四件事全部核实通过；TASK-057 的实现**没有**未完成的功能项，缺的只是**报告**与**若干机器证据**，本报告补齐）
- **结论锚点（D86）**：
  - **被核实对象的实现提交**：`96f631addb193b1c23eee821e9ee18d564b96d54`（`--short=9`：`96f631addb`，分支 `feature/mcp-server-module`）
  - **本报告的最终提交**：本文件所在的 HEAD（自引用；见 §8 与 §8.1 的提交序列 `6128298272` → `9058e41d82` → 本提交）
- **契约**：175 条（`docs/tools_list.renamed.json`，142227 B）
- **两个二进制在 `96f631addb` 上的锚点**（本任务核实全部四件事时所测）：
  - plain：`4.8.dev.custom_build.96f631add`
  - mono：`4.8.dev.mono.custom_build.96f631add`
- **两个二进制在报告提交后的复验锚点**（§8，重建于 `6128298272`）：
  - plain：`4.8.dev.custom_build.612829827`
  - mono：`4.8.dev.mono.custom_build.612829827`
- **工作树收尾**：只剩既有未跟踪物 **4 个**（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`）
  ＋ 本任务的任务书 `modules/mcp_server/docs/tasks/TASK-058-recover-057-report.md`（TASK-058 新增、待提交）

---

## 0. `96f631addb` 到底改了什么（只读核实）

`git show --stat 96f631addb`：

| 文件 | 增/删 | 对应 TASK-057 的哪件事 |
|---|---|---|
| `core/config/project_settings.cpp` | +448 / -0 | 引擎补丁 2（`update_settings_section_text` / `save_custom_section` / `_save_custom_section_bnd` / ClassDB 绑定） |
| `core/config/project_settings.h` | +35 / -0 | 引擎补丁 2（两个新方法 + 长注释） |
| `modules/mcp_server/docs/scripts/check_tool_groups.py` | +128 / -2 | R-B2（`--generator-version` + `assert_generator_version_consistency`） |
| `modules/mcp_server/docs/tool-groups-added.json` | +2 / -1 | R-B2（新增 `source.generator_version: "1.17.0"`） |
| `modules/mcp_server/scripts/mcp056_regression_battery.ps1` | +104 / -7 | R-B3（`%TEMP%` 日志 + 自动还原 + 清单） |
| `modules/mcp_server/scripts/mcp057_build_mono.cmd` | +82 / -0 | D-B1（把 mono 构建命令**写进仓库**） |
| `modules/mcp_server/scripts/mcp057_gates.ps1` | +95 / -0 | 门脚本 |
| `modules/mcp_server/scripts/mcp057_rb2_failure_demo.ps1` | +184 / -0 | R-B2（失败演示） |
| `modules/mcp_server/scripts/mcp057_section_probe.gd` | +111 / -0 | 引擎补丁 2（活证据探针） |
| `modules/mcp_server/scripts/mcp057_settings_publish_evidence.ps1` | +375 / -0 | 引擎补丁 2（字节级证据） |
| `modules/mcp_server/scripts/mcp_evidence_guard.ps1` | +152 / -0 | R-B3（快照/还原助手） |
| `modules/mcp_server/tests/test_mcp_server.h` | +420 / -0 | 引擎补丁 2 的 4 个 doctest |

**12 个文件，+2136 / -10。** 关键事实：

- **没有触碰任何 `modules/mcp_server/tools/**`**：`git show --stat 96f631addb -- modules/mcp_server/tools/` 为空；
  `git diff --stat 427fc79da2..96f631addb -- modules/mcp_server/tools/` **为空**（`427fc79da2` 是 TASK-057 的父提交）。
- **没有触碰契约**：`docs/tools_list.renamed.json` 与 `tool-groups.json` 均不在改动清单内。
- 引擎侧改动是**纯增**（+448 / +35，0 删除行），`project_settings.cpp` 既有函数体一行未改。

各文件的 sha256（本任务实测，工作树当前字节）：

```
8df3ea2e2d2896e9fe8f3510de2856549731fab777dd1183c36d5b8fbf0d8997  core/config/project_settings.cpp
e8d7743dd18c006f1b7d2f54b488d71d1581577d85b13a706a560d2363a567fc  core/config/project_settings.h
69534eb1d978656cf1617b1ea6fc60cd20ea90c7c286bfdc0325afc9b01884e4  modules/mcp_server/docs/scripts/check_tool_groups.py
3bb522d99a2a52309f963b97b975e1396ad31df7bb81cfe135414792d900ff81  modules/mcp_server/docs/tool-groups-added.json
bdd0fffe4d05318de93040e5a136bdc2b28584b044f34d13127bd79c048c0014  modules/mcp_server/scripts/mcp_evidence_guard.ps1
9f84441402a7bf51f76e363653b587fdfaff5ca6d7daa5d33ad75eff5b75b89d  modules/mcp_server/scripts/mcp056_regression_battery.ps1
ad3bf20cbdd0e77c592dcfbc47c0f9a5a4955f71c40c993023458e27443f8dff  modules/mcp_server/scripts/mcp057_gates.ps1
280858e2fb72ebac6b0364bf8bb69312ff257105d649f01b6d6e94a0a1091b49  modules/mcp_server/scripts/mcp057_rb2_failure_demo.ps1
c370fdaaf2703832b75df08cbe967e0a225b4b7de0cbac8e1912b2ad590970ce  modules/mcp_server/scripts/mcp057_settings_publish_evidence.ps1
8f7051d39479a47855be8186bdce4a9089f76a8390628a4c8c2da17d92dcbe26  modules/mcp_server/scripts/mcp057_build_mono.cmd
a111799a14585126b9402fa05e0fdb92714c84398f3c8759e1296b51d772fe87  modules/mcp_server/scripts/mcp057_section_probe.gd
cdce026b87e8c3579c3045353624cea0be41b05adb9f2d83488ee229d1d059d4  modules/mcp_server/tests/test_mcp_server.h
```

> 注：这些 sha256 是**本任务工作树的实测值**，与 `96f631addb` 提交时的内容一致（工作树对这些文件是干净的）。

---

## 1. 事件 ①：D-B1（mono 二进制是脏树构建）

### 1.1 缺陷回顾

TASK-056 遗留：`bin\godot.windows.editor.x86_64.mono.console.exe` 自报 `4e3de1090` ≠ 当时的 HEAD `427fc79da`
（构建于提交前），导致 `mcp052` 与 `mcp053` **唯一**失败项 `engines_match_head`。

### 1.2 TASK-057 做了什么

新增 `scripts/mcp057_build_mono.cmd`（82 行，跟踪进仓库）——把**从未被记录**的 mono 构建命令写下来：
`D:\Anaconda\Scripts\scons.exe platform=windows target=editor module_mono_enabled=yes tests=yes -j8`，
并删除三类陈旧对象（`test_mcp_server`、`test_main`、以及 `mcp_trace` 的**两个变体**对象），
日志写 `%TEMP%`、**不抑制 scons 输出**、退出码原样传递。**该文件本身不构建**，是"命令的记录"。

### 1.3 本任务核实

**二进制锚点（只读实测）**：

| 二进制 | `--version` | 结论 |
|---|---|---|
| `bin\godot.windows.editor.x86_64.exe`（plain） | `4.8.dev.custom_build.96f631add` | == HEAD ✅ |
| `bin\godot.windows.editor.x86_64.console.exe`（plain console） | `4.8.dev.custom_build.96f631add` | == HEAD ✅ |
| `bin\godot.windows.editor.x86_64.mono.console.exe`（mono） | `4.8.dev.mono.custom_build.96f631add` | == HEAD ✅，且含 `.mono.` 标记 ✅ |

→ **两个二进制都自报当前 HEAD，说明 mono 干净树重建已做。** D-B1 的**目标已达成**。

**复跑到目标计数（本任务实跑，非转述）**：

| 脚本 | 目标 | 实测 | 退出码 | 证据 |
|---|---|---|---|---|
| `mcp052_added_tools_evidence.ps1` | 53/53 | **53/53 checks passed** | 0 | `%TEMP%\mcp052\evidence`，log sha256 `5bd1d530ef994121629de895cd5f20d67dbfd30c9c77e9233eda75701b17ab7b` |
| `mcp053_added_tools_evidence.ps1` | 73/73 | **73/73 checks passed** | 0 | `%TEMP%\mcp053\evidence`，log sha256 `93ee4350956239bf537aa0b1c0ad949115cc4d564600b23d4231531e7ef3b06c` |

`engines_match_head` 的断言内容（源码核实）：`mcp052…:274` / `mcp053…:317` 同时要求
**plain 与 mono 两个 `--version` 都包含 `git rev-parse --short=9 HEAD`**；
另有 `mono_engine_is_the_mono_build`（`:276` / `:319`）要求 mono 版本号含 `.mono.`。
两条都通过 → 本项 53/53 与 73/73 的达成**确实**归因于 mono 重建，而非放宽断言。

### 1.4 遗留风险（如实记录）

`mcp057_build_mono.cmd` 里 **硬编码了 `D:\Anaconda\Scripts\scons.exe` 的绝对路径**。
在本机可用（本任务的 mono 重建即用它），但在别的机器/CI 上会失败。
它不是本批的验收项，记录为已知限制（见 §6 D-5）。

---

## 2. 事件 ②：R-B2（生成器版本一致性变成机器断言）

### 2.1 缺陷回顾

`docs/tool-groups-added.json` 的 `source.entries` 版本号曾是**自由文本**，`check_tool_groups.py` **完全不校验**，
导致漂移静默复发（本类已复发两次：一次对生成器，一次 TASK-056 D2）。

### 2.2 TASK-057 做了什么

- `tool-groups-added.json` 新增**机器可读字段** `source.generator_version: "1.17.0"`，
  并把 `source.entries` 的自由文本改为**仍包含**该版本号（便于人读，且被断言"不得提到别的号"）。
- `check_tool_groups.py` 新增 `assert_generator_version_consistency()`，断言**三处必须相等**：
  1. `scripts/gen_renamed_contract.py` 的 `GENERATOR_VERSION`（正则 `^GENERATOR_VERSION\s*=\s*"([^"]+)"\s*$` 提取）；
  2. `docs/tools_list.renamed.json` 的 `_meta.generator_version`；
  3. `docs/tool-groups-added.json` 的 `source.generator_version`。
  并额外要求 `source.entries` **至少提到**同一版本号（"散文可以多说，不能少说/说错"）。
- 该断言被 `main_added()` **首先**调用（所以 `--added` 也覆盖它），另加**独立入口** `--generator-version`。
- 新增 `mcp057_rb2_failure_demo.ps1`：对三处**逐一**制造漂移 → 断言必须 exit 非 0 → **字节级还原** → 基线复绿。

### 2.3 本任务实测

**断言本身（基线，应绿）**：

```
SOURCE  GENERATOR_VERSION (../scripts/gen_renamed_contract.py)            = 1.17.0
SOURCE  contract _meta.generator_version             = '1.17.0'
SOURCE  tool-groups-added.json source.generator_version = '1.17.0'
ASSERT  GENERATOR_VERSION == _meta.generator_version == source.generator_version: PASS (1.17.0)
ASSERT  source.entries contains the same version string: PASS
GENERATOR-VERSION CHECK PASS (1.17.0)
EXIT=0
```

（`python modules\mcp_server\docs\scripts\check_tool_groups.py --generator-version`）

**失败演示（三处逐一漂移 → 必须非 0 → 还原）**：

```
rb2_failure_demo|exit=0|SAME 9c70605436a5b559eb973434d9cda6d6a9e0c6bef9ec3318d409137f2ba288f5 tools_list.renamed.json |
  R-B2 FAILURE DEMO: PASS (three drifts detected, three byte-exact restores, baseline green)
```

→ 演示的**自身**退出码是 0（它成功完成了"三次漂移都被检出 + 三次字节还原"），
但内部证明了三处漂移各自都让被瞄准的检查**退出非 0**。演示对 `tools_list.renamed.json`
在前后各算了一次 SHA256，**前后相同**（`9c706054…`），即还原是字节精确的。

**`--added` 也覆盖该断言（实测）**：`--added` 的输出里可见
`ASSERT GENERATOR_VERSION == _meta.generator_version == source.generator_version: PASS (1.17.0)`
在其自身清单断言**之前**；退出码 0；清单 SHA256 `3bb522d99a2a52309f963b97b975e1396ad31df7bb81cfe135414792d900ff81`，
`--check-completeness` 报同一 SHA256（两者一致）。

**判定**：R-B2 的三处一致已成为**机器断言**，且漂移可被**复现地**检出。✅

---

## 3. 事件 ③：R-B3（回归电池不得静默覆写被跟踪证据）

### 3.1 缺陷回顾

15 步回归里 13 步会重写 `docs/reports/evidence/task0xx/**` 的**被跟踪**文件
（`mcp051` 还会**新建** `task051/red/e20_child_status.json`）→ 重跑会**静默改写历史取证**，
人工 `git checkout --` 才补得回来。

### 3.2 TASK-057 选的路（二选一的②）+ 理由

新增共享助手 `scripts/mcp_evidence_guard.ps1`（152 行）：`Get-McpEvidenceState` 用
`git status --porcelain -unormal` 拍快照（"未跟踪目录保留为一条以 `/` 结尾的记录"，
使还原成为一次 `Remove-Item`）；`Restore-McpEvidence` 把**新增的 modified** `git checkout --` 回去、
把**新增的 untracked** 删除，**不动**运行前就已经脏的文件（并打印 `KEPT-DIRTY-BEFORE-THE-RUN`），
最后打印 `SUMMARY restored=… removed=… kept-dirty-before=…`。

`mcp056_regression_battery.ps1` 的改动**只有两处**（源码注释亦是此措辞）：
① 聚合日志目录**默认改到 `%TEMP%`**（`-EvidenceDir` 仍可指回历史路径；`-NoRestore` 可关闭还原）；
② 运行前拍快照、运行后还原并**打印清单**，且**若 `git diff --stat` 不为空则电池自己失败**。

**为什么没选①（每步改写到 `%TEMP%`）**：13 个步骤脚本的输出路径是**各自任务书声明的证据契约**
（冷冻报告引用它们），逐脚本改路径会改动 13 份报告引用的路径；快照/还原对所有步骤（含将来新增步骤）都成立，
且**不改任何一个写入者**。理由写进了助手文件头注释。**该选择合理。**

### 3.3 本任务实测（本任务重跑电池）

```
--- git status --short (before) ---
    ?? .graphifyignore
    ?? build-m0.cmd
    ?? graphify-out/
    ?? install-deps-m0.cmd
    ?? modules/mcp_server/docs/tasks/TASK-058-recover-057-report.md
--- git diff --stat (before): 0 line(s) ---
…
--- R-B3 restore manifest (TASK-057 section 3) ---
    RESTORED modules/mcp_server/docs/reports/evidence/task050/red/e03_n2_validate_cs.response.json
    … （共 66 条 RESTORED，task050 / task051 / task053 三个目录）…
    REMOVED modules/mcp_server/docs/reports/evidence/task051/red/e20_child_status.json
    SUMMARY restored=66 removed=1 kept-dirty-before=0
--- git status --short (after) ---
    ?? .graphifyignore
    ?? build-m0.cmd
    ?? graphify-out/
    ?? install-deps-m0.cmd
    ?? modules/mcp_server/docs/tasks/TASK-058-recover-057-report.md
--- git diff --stat (after): 0 line(s) ---
…
tracked_evidence_restored|0|git diff --stat after=0 line(s); newly modified=0; newly untracked=0; restore failures=0
```

- **重跑前**：`git diff --stat` 0 行；未跟踪 5 项（4 个既有 + 本任务任务书）。
- **重跑后**：`git diff --stat` **0 行**；未跟踪**仍是同样 5 项**（逐条相同）；`newly modified=0`、`newly untracked=0`。
- 还原清单 **66 RESTORED / 1 REMOVED / 0 kept-dirty** ——被跟踪证据**逐字节回到 HEAD**，
  且那个"电池新建的文件"被删除。

**判定**：R-B3 达成，且"证据仍是历史"是**断言**（电池在 `git diff --stat` 非空时自己失败），不是纪律。✅

---

## 4. 事件 ④：引擎补丁 2 —— `ProjectSettings` 的局部发布

### 4.1 选了哪条面：**最优（第 1 条）**

TASK-057 任务书给了三条优先级：

| 面 | 内容 | 本批选择 |
|---|---|---|
| **1（最优）** | 引擎侧提供"只更新某一节/某一组键"的写出口，使注释与其余文本逐字保留 | ✅ **选这条** |
| 2（次优） | 暴露 `_save_settings_text` 的分节输出，由上层做"按节替换" | ✗ 未选 |
| 3（保底） | 不做，把整文件重写保持为已声明行为 | ✗ 未选 |

**落点与依据（`文件:行`）**：

| 内容 | 位置 | 依据 |
|---|---|---|
| `static Error update_settings_section_text(const String &, const String &, const CustomMap &, String &)` | `core/config/project_settings.h:230`（声明）→ `core/config/project_settings.cpp:1537`（定义） | 文本半边，**无 I/O**，便于按字节单测 |
| `Error save_custom_section(const String &, const String &, const CustomMap &)` | `project_settings.h:229` → `project_settings.cpp:1682` | I/O 半边：读原文 → 只替换目标节 → 写回 |
| `Error _save_custom_section_bnd(...)` + `ClassDB::bind_method(D_METHOD("save_custom_section", …))` | `project_settings.cpp:1779` / `:2104` | 让 GDScript 探针可调用（活证据） |
| 目标节序列化 | `project_settings.cpp:1551-1559`，用 `VariantWriter::write_to_string(E.value, written, true)` | **与 `_save_settings_text()` 同一个 writer**，所以落进文件的是"整文件保存该设置"会写的同一串字节 |
| 扫描器 | `_ps_scan(p_text)`（同提交新增的字符级扫描） | 提交信息记载：非空 `Dictionary` 会被引擎**跨多行**序列化（`variant_parser.cpp:2187-2201`），**按行**读取会把值体留在后面 → 必须**按字符**走 |

**为什么选最优**：它把"文本手术"整件搬进引擎（上层不做任何文本拼接），因此 R1（`[input]` 非末节时键落错节）
这一**可复现静默失败**由引擎的节边界识别消除，而注释/键序/BOM/CRLF 的保留由"只替换目标节的字节跨度、
其余原样拷贝"这一结构保证。任务书要求的"**必须由引擎自己序列化目标节（不得让上层做文本手术）**"因此满足。

**代价**（如实记录）：
- 引擎侧新增 483 行（含长注释），维护面在 `core/`；
- 写入是"**兄弟临时文件 + 备份 + rename**"（`project_settings.cpp:1738-1776`），
  且 `DirAccess::remove_absolute(p_path)` 与 `rename_absolute(temp, p_path)` 之间有极小窗口 ——
  这不是 POSIX `rename()` 的原子替换语义；代码用"备份 + 失败时回滚"覆盖它。
  这是**有意的取舍**，且在 §4.6 的并发证据里被**诚实声明**为"不保证 no-lost-update"。
- 新增 1 个窄化点（`(int)length`，`project_settings.cpp:1721`），见 §5。

### 4.2 既有 175 条工具行为逐字节不变 —— **只提供 API，未切换行为**

**结论：本批没有切换任何工具的行为。`editor_add_input_action` 只提供 API，未切换行为。**

证据（三条，互相独立）：

1. **提交没碰任何工具文件**：`git show --stat 96f631addb -- modules/mcp_server/tools/` **为空**；
   `git diff --stat 427fc79da2..96f631addb -- modules/mcp_server/tools/` **为空**。
2. **没有任何工具调用新 API**：`findstr /S /N /I "save_custom_section update_settings_section_text" modules\mcp_server\tools\*.cpp modules\mcp_server\tools\*.h`
   → **零命中**。新方法的调用者只有引擎自己的绑定、doctest 与 GDScript 探针。
3. **契约未变**：契约与 `tool-groups.json` 都不在改动清单内；门① 的逐字断言在编辑器 9888 / 游戏 9889 上
   仍 `3/3 checks passed`；契约 175 条、`_meta.map_sha256` 未动。

**`project_set_setting` 等仍整文件重写**——活证据（`mcp057_settings_publish_evidence.ps1`，
`p2_save_custom_still_rewrites_the_whole_file`）：

```
[PASS] p2_save_custom_still_rewrites_the_whole_file :: header_written=True hand_comments_gone=True
       (declared behaviour, deliberately unchanged)
```

即：对同一个带手写注释的 fixture 调 `save_custom()`，仍然写出 `; Engine configuration file.` 头、
仍然丢掉手写注释 —— **声明行为未被本批改变**。

**契约里的陈述仍然为真且未改**：5 个工具的 `description` 里写着
"…rewrites the entire project.godot with the engine's own whole-file writer (**the engine has no partial-publish API**)…"
（`tools_list.renamed.json` 第 93 / 787 / 1572 / 2201 / 2220 行）。
其**行为陈述**（整文件重写、丢注释、幂等）在**本批**仍成立；
但括号里的那句 "the engine has no partial-publish API" **已被本补丁证伪**。
按手册 §7.2（契约由决策者维护、实现者只报缺陷），**本任务不改契约描述**，列为缺陷 **D-4**（§6），请决策者另批切换。

### 4.3 注释与其余文本逐字保留 —— 字节级证据

**最硬的一条：LF fixture 的"实际 vs 独立构造的期望"逐字节相等。**

fixture（`[input]` **故意不是末节**）：

```
; HAND WRITTEN HEADER -- must survive byte for byte
; second comment line
[application]

config/name="mcp057-fixture"
config/features=PackedStringArray("4.8")
run/main_scene="res://scenes/main.tscn"

; input is deliberately NOT the last section
[input]

mcp057_existing={
"deadzone": 0.5,
"events": []
}

[rendering]

renderer/rendering_method="gl_compatibility"
```

调用 `ProjectSettings.save_custom_section(res://project.godot, "input", {"input/mcp057_fire": {"deadzone":0.5,"events":[]}})`
之后：

```
[PASS] p2_publish_returns_ok :: MCP057_PROBE mode=input_action err=0
[PASS] p2_probe_keys_read_back :: MCP057_PROBE keys=["mcp057_existing", "mcp057_fire"]
[PASS] p2_probe_key_present :: MCP057_PROBE key=mcp057_fire present=true
[PASS] p2_file_changed_by_publish :: before=76d087d8… after=5453ba95…
[PASS] p2_bytes_exact_lf :: actual=409B sha=5453ba95e75b5ef9bb39caf20a9227edf501d73ce4c3534fd17234630d03d0e6 expected=409B
```

**本任务独立复核**（不信报告、自己比字节）：

```
Hash                                                             Length
5453BA95E75B5EF9BB39CAF20A9227EDF501D73CE4C3534FD17234630D03D0E6  lf_actual.godot    409
5453BA95E75B5EF9BB39CAF20A9227EDF501D73CE4C3534FD17234630D03D0E6  lf_expected.godot  409
byte_identical=True lengths=409/409
```

→ 实际写入的 409 字节与**在 PowerShell 里独立构造的**期望 409 字节**逐字节相同**
（期望 ~ 由 fixture 自身字节派生：把已有 `mcp057_existing=` 的**多行块**换名而来，
因此期望天然带"引擎真实的多行格式"）。注释、空行、键序、后面的 `[rendering]` 全在其中。

**`[input]` 非末节的反例（RED）——把选这条路的原因钉死**：

```
[PASS] p2_RED_naive_splice_is_silent_and_wrong :: has_action=False (expected false) file_still_parses=True -- the failure is silent
[PASS] p2_RED_naive_splice_put_the_key_in_rendering :: the key sits after the [rendering] header, which is why the InputMap cannot see it
```

即：**被否决的文本拼接**把新键追加到文件末尾，文件**仍然能被 `ConfigFile` 正常解析**（`load=0`），
但引擎自己的 `InputMap.has_action("mcp057_fire")` 是 **false** —— 键落在 `[rendering]` 之下。
这正是 R1 的**静默**失败，也正是补丁存在的理由。
对照：走新路径后 `p2_has_action_true_after_publish_R1_reversed` 为 **true**；
且发布**之前**的负对照 `p2_has_action_control_false_before_publish` 为 **false**（证明读者**能**说"没有"）。

**幂等**：

```
[PASS] p2_idempotent_second_call :: sha after first=5453ba95… sha after second=5453ba95…
```

第二次同样的调用**不改一个字节**（源码 `project_settings.cpp:1728-1733`：`updated == text` 时**直接返回**，
连文件都不碰）。doctest 里另有 `TASK-057 section publish keeps CRLF, creates a missing section and is deterministic`
覆盖重复调用的确定性。

**新节创建的形状**（`p2_new_section_appended_at_end`）：
`ends_with_block=True starts_with_previous=True` —— 新节按 `_save_settings_text()` 的形状追加在**文件末尾**，
且此前内容**原样保留**。

**BOM**：

```
[PASS] p2_bom_preserved :: before[0..2]=EF BB BF after[0..2]=EF BB BF
```

实现侧（`project_settings.cpp:1712-1721`）**显式**处理：`get_as_text()` 会**丢掉** BOM、`store_string()` 从不写 BOM，
所以代码先探测 `raw[0..2] == EF BB BF` 再 `String::chr(0xFEFF)` 补回，然后 `append_utf8`。
注释明确写"measured, not assumed"。doctest
`TASK-057 save_custom_section preserves the BOM and every byte outside the target section` 另在字节层面断言 `after[0..2]`。

**CRLF**：

```
[PASS] p2_crlf_preserved_and_new_line_is_crlf :: no_bare_lf=True inserted_with_crlf=True
```

全程**没有裸 LF**，新插入的行也用 `\r\n`。实现取"文件第一个有终止符的 statement 的终止符"作为该文件的行尾
（`project_settings.cpp:1631-1637`）。

**`--import` 与游戏运行后不变**：

```
[PASS] p2_import_leaves_file_unchanged :: import exit=0 attempts=1 sha 0b78ad13… -> 0b78ad13…
[PASS] p2_game_run_leaves_file_unchanged :: run exit=0 sha 0b78ad13… -> 0b78ad13…
```

（`--import` 走共享助手 `Import-McpProject`：退出码被校验、有界重试、diagnosable。游戏运行用 `--quit-after 2`。）

**并发**：

```
[PASS] p2_concurrency_four_writers_all_exit_zero :: …4 个进程都 exit 0；still running after the wait: 0
[PASS] p2_concurrency_bytes_outside_the_section_untouched :: the prefix before [input] and everything from [rendering] on are byte identical to the fixture
[PASS] p2_concurrency_every_line_is_a_whole_result :: survivors=4 duplicated=0 unexpected line(s)=
[PASS] p2_concurrency_no_scratch_file_left :: no .section_tmp / .section_bak next to the destination
```

四个并发写者的结果：**没有任何撕裂/半合并**（每一行都是一个完整结果、无重复行、目标节外的字节与 fixture 逐字相同、
无残留 scratch 文件）。**脚本诚实地声明**它**不**保证 no-lost-update（读-改-rename 无跨进程锁，"last writer wins"），
所以断言只接受 1–4 个**完整**结果，拒绝任何**部分**结果 —— **这是正确的写法**（保证要说真的那句）。

### 4.4 若动了 `editor_add_input_action` 的行为 → 单列「行为变更」

**没有动。** 明确结论：**本批只提供 API，未切换行为。**
`editor_add_input_action`（`modules/mcp_server/tools/editor_input_simulation.cpp:1329`）的描述与行为都**未改**；
TASK-057 任务书 §4④ 说"**否则**本批只提供 API、不改行为，由我另批切换" —— 本批正是这个分支。
**因此本报告没有「行为变更」一节**（没有变更可列），并把"契约描述已被证伪"单列为缺陷 D-4。

### 4.5 doctest（红/绿）

`modules/mcp_server/tests/test_mcp_server.h` 新增 **4 个 `[MCPServer]` 用例**（+420 行）：

1. `TASK-057 section publish puts the key in the named section even when it is not the last one`
   —— 非末节落位、幂等、重复发布改写而非追加、`foreign` 键（不属于该节）→ `ERR_INVALID_PARAMETER`、
   空 `CustomMap` → 原文不变；
2. `TASK-057 section publish keeps CRLF, creates a missing section and is deterministic`
   —— CRLF 无裸 LF、新节形状与确定性、非法节名（`""` / `"in]put"`）→ `ERR_INVALID_PARAMETER`；
3. `TASK-057 save_custom_section preserves the BOM and every byte outside the target section`
   —— 磁盘路径的 BOM 三字节、目标节外逐字节、幂等、缺文件 → `ERR_FILE_NOT_FOUND`（且**不创建**）、
   `foreign` → `ERR_INVALID_PARAMETER`（且文件**不变**）、无残留 `.section_tmp` / `.section_bak`；
4. `TASK-057 section publish replaces a multi-line value without leaving its body behind`
   —— **多行 `Dictionary` 值**的替换（`"deadzone"` 与 `"events"` 各恰好出现 2 次、`}` 恰好 2 个），
   值与键都在、旧值体不留残、且替换后**前缀/后缀与原文字节相同**。

**红/绿证据的局限（如实说）**：TASK-057 的执行者**没有**留下"红阶段"的真实输出
（它写完代码即中断，报告缺失）。本任务**无法**倒推红阶段日志。
但**绿阶段**是可重跑且已重跑：门③ `332 passed | 0 failed`（含这 4 个新用例）、门④ `1758 passed | 0 failed`。
**独立性**另有保障：这 4 个用例断言的行为**同时**被 `mcp057_settings_publish_evidence.ps1` 的
**进程外**字节比对与**引擎自己的 `InputMap`** 复核（§4.3），不依赖 doctest 自身。
"红阶段缺失"列为缺陷 **D-3**（§6）。

### 4.6 补丁 2 证据脚本的两处自证缺陷（如实记录，见 §6 D-1 / D-2）

`mcp057_settings_publish_evidence.ps1` 里：

- **D-1**：`Check 'p2_concurrency_four_writers_all_exit_zero'` 在 `:319` 与 `:332` **被调用两次**
  （两个 `Check` 参数不同但**同名**）→ 汇总里同一 ID 出现两行、`checks: 24` 里含一个重复项。
  **不影响判定**（两行都 PASS），但是报告卫生缺陷。
- **D-2**：`Check 'p2_no_scratch_engine_process_left' ($swept.Count -eq 0 -or $true) …`（`:364`）
  —— `-or $true` 使该断言**恒真**，是一次真正的空断言（tautology）。它自称"检查没有残留进程"，
  实际**不检查**。**不影响本任务结论**（本任务实测 sweep 数为 0，且电池收尾时端口空闲），
  但**必须**如实记录，不得当作有效证据。

这两处都是**本任务新发现**，不在 TASK-057 任务书的四件事里；因为要动的是"证据脚本自身质量"，
本任务**不自行修改脚本**（避免改动已被提交的取证工具并让本报告与提交的脚本不一致），
而是**在报告里报告**，交决策者决定是否另批修。

---

## 5. 收窄点清单（GDR-24 / §22.3b 规则 2、4）：**新增点 × 它经过的闸门 × 证据**

引擎补丁 2 在 `core/config/project_settings.cpp` 里只有**一个**窄化点（本任务代码审查的结论）：

| 新增点 | 位置 | 形态 | 经过的闸门 | 证据 |
|---|---|---|---|---|
| `text.append_utf8((const char *)raw.ptr(), (int)length);` | `project_settings.cpp:1721` | **整数窄化**：`uint64_t length` → `int` | **显式前置范围闸门**：紧邻的 `:1701` 行 `ERR_FAIL_COND_V_MSG(length > (uint64_t)INT32_MAX, ERR_OUT_OF_MEMORY, …)` 在转换**之前**拒绝任何装不进 `int` 的长度 | ① 源码：`:1695-1706`（读长度、范围检查、resize、读取、`read != length` 检查）；② 行为：文件本身不可达 2 GiB，且超限**拒绝而非截断**；③ 注释：`:1696-1700` 自述"refusing is the only honest answer here"，并**指向本报告** |

**闸门⑥ 的边界（必须说清，不得含糊）**：`check_narrowing_points.py` 的 `--coverage` 输出明写
"anything outside `tools/**` (the module's other sources and the engine are not scanned)"。
本任务的实测输出：

```
scanned     : 75 narrowing point(s) in 16 file(s)
pinned      : 75
```

→ 当前树 `scanned == pinned`（75/75），**但引擎文件根本不在扫描范围内**
（`core/config/project_settings.cpp` 无 `MCP-NARROWING` 标记、也不在 `PINNED` 清单里）。
所以**门⑥ 对本补丁的新增窄化点不提供任何保证**；该点的保证来自上表的"显式前置范围闸门 + 代码审查 + 行为证据"
这三条腿。**不得**把门⑥ 变绿当作引擎侧窄化的证据。
另据 TASK-031 的修订（手册 §3 门⑥ 注），门⑥ 的保证本来就是"**有限集合**"的；引擎侧落在集合外属已知边界。

**门⑥ 的其他实测**：`--coverage` 报 11 处 **pinned 行号漂移**（`pinned_line` 与 `now` 不等），
按脚本自己的说明"pin 是按 marker id + occurrence，所以不是失败"，**exit 0**；
覆盖探针 `mcp031_gate6_coverage_probes.ps1` 报 **101/101 checks passed**（含 `B1b_restored_byte_identical`、
`B1b_worktree_clean_of_probes` —— 即探针插删后**字节还原**、工作树干净）。

---

## 6. TASK-057 未完成 / 做错的地方（如实列出）+ 本任务做了/没做什么

**总判**：TASK-057 的**功能实现四件事全部达成**（D-B1 目标达成、R-B2 达成、R-B3 达成、引擎补丁 2 达成且按最优面实现）。
**未完成的是"报告与取证收尾"**，本报告补齐；另有若干**实现/取证质量缺陷**如下。

| ID | 级别 | 内容 | 本任务做了 | 是否需改规范 |
|---|---|---|---|---|
| **D-3** | medium | **`AGENTS/手册 §3` 要求的"红阶段与绿阶段真实输出"缺失**：TASK-057 未留任何红证据（`96f631addb` 只有绿侧）。本任务**无法倒推**红阶段。 | 如实记录；**用独立证据补强**：4 个新 doctest 的绿侧（门③ 332/332）＋**进程外**字节比对＋**引擎 InputMap** 的活证据（§4.3/4.5）。不伪造红阶段。 | 否（属取证缺口，报给决策者） |
| **D-6** | medium | **TASK-057 报告路径自相矛盾**：任务书标题写 `…-project-settings-publish.md`，正文第 4 行写 `…-settings-publish.md`。执行者按其中哪一个都没写成报告（中断）。 | 采用 TASK-058 §1.4 指定的 `docs/reports/REPORT-057-mono-anchor-and-settings-publish.md` 并在此声明。 | **是** → 请决策者裁定唯一路径并修正 TASK-057 任务书标题 |
| **D-4** | medium | **契约描述已被补丁证伪**：5 个工具的 `description` 仍说 "the engine has no partial-publish API"（`tools_list.renamed.json:93/787/1572/2201/2220`）。**行为陈述仍真**，括号里的能力陈述已假。 | **不改契约**（手册 §7.2；改描述会动契约 sha/文档指纹）。列为缺陷并给出位置，请决策者另批处理（很可能与"把 5 个工具切到新路径"的批一起）。 | **是** → 需决策者另批切换描述/行为 |
| **D-1** | minor | `mcp057_settings_publish_evidence.ps1` 的 `p2_concurrency_four_writers_all_exit_zero` 被 **`Check` 两次**（`:319`/`:332`）→ 汇总重复行、计数含重复项。 | 记录；**不自行改**已提交的取证脚本（避免报告与提交的脚本不一致）。 | 否 |
| **D-2** | minor | 同上脚本 `:364` `p2_no_scratch_engine_process_left` 的判据是 `($swept.Count -eq 0 -or $true)` → **恒真空断言**，不检查任何东西。 | 记录；本任务**独立**确认收尾时端口 9888/9889 空闲、无本任务 scratch 进程（见 §7）。不自行改脚本。 | 否 |
| **D-5** | minor | `mcp057_build_mono.cmd` 硬编码 `D:\Anaconda\Scripts\scons.exe` 绝对路径 → 只在有该解释器的机器上可跑。 | 记录为已知限制（本机可用，mono 重建已在其上完成）。 | 否（可选改善） |
| **D-7** | info | `core/config/project_settings.cpp` 的 `save_custom_section` 用"删原文件 + rename"而非 POSIX 原子替换，`remove`→`rename` 之间有极小窗口；脚本已诚实声明不保证 no-lost-update。 | 记录为**有意取舍**（有备份 + 失败回滚 + 并发不撕裂证据）。 | 否 |

**明确"不需要改规范"的确认**：本任务**未发现**需要修改 `docs/DESIGN-DETAIL.md` 的情况；
**未修改** `DESIGN-DETAIL`（任务书硬性纪律）。若决策者认为 D-4/D-6 需要改规范，请在下发下一批时明确。

---

## 7. 门与回归：本任务的真实输出与退出码

### 7.1 构建基线（门必须先绑定构建，R-1）

**本任务没有重建**——两个二进制都自报当前 HEAD `96f631add`（§1.3），说明 TASK-057 的
`build_local.cmd -Force` + `mcp057_build_mono.cmd` 已把两个变体都锚在 HEAD 上。
门脚本 `mcp057_gates.ps1` 在**开头**自己打印并断言这件事：

```
engine --version: 4.8.dev.custom_build.96f631add
git HEAD short : 96f631add
version_matches_head: True
```

### 7.2 五道门 + 门⑥ 三段式 + 契约检查（全部本任务实跑）

命令：`powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp057_gates.ps1`（串行、从 cmd 启动、不抑制输出）
日志：`%TEMP%\mcp057\gates\20260925-031043\`，控制台副本 `%TEMP%\t058_gates_console.txt`

| 门/检查 | 结果 | 退出码 |
|---|---|---|
| ① 契约逐字（默认 + 4 组） | `group=… tools=… contract=175 \| implemented_union=152 tools (editor) / 72 tools (game) \| 3/3 checks passed`（5 次运行全同） | 0 ×5 |
| ③ 模块 doctest (`--test-case="[MCPServer]*"`) | `test cases: 332 \| 332 passed \| 0 failed \| 1429 skipped`；`assertions: 23625 \| 23625 passed \| 0 failed`；`Status: SUCCESS!` | 0 |
| ④ 全引擎回归 (`--test`) | `test cases: 1758 \| 1758 passed \| 0 failed \| 3 skipped`；`assertions: 447860 \| 447860 passed \| 0 failed`；`Status: SUCCESS!` | 0 |
| ⑥a 收窄点清单 | `scanned=75 / pinned=75`，0 误报 | 0 |
| ⑥b `--coverage` | 打印已声明集合与**集合外**说明；11 处行号漂移（非失败） | 0 |
| ⑥c 覆盖探针 | `101/101 checks passed`；`B1b_restored_byte_identical \| B1b_worktree_clean_of_probes` | 0 |
| `--check-completeness` | `BYTES ADDED 5852 \| SHA256 ADDED 3bb522d9… \| TOOL-GROUPS-COMPLETENESS CHECK PASS` | 0 |
| `--added` | `BYTES 5852 \| SHA256 3bb522d9… \| TOOL-GROUPS-ADDED CHECK PASS`（与 completeness 同 SHA256） | 0 |
| R-B2 断言（`--generator-version`） | `PASS (1.17.0)`，三处一致 | 0 |
| R-B2 失败演示 | `three drifts detected, three byte-exact restores, baseline green` | 0 |
| 补丁 2 活证据 | `checks: 24, failures: 0` → `SETTINGS-PUBLISH EVIDENCE PASS` | 0 |
| **整体** | `ALL GATE STEPS EXIT 0` | **0** |

> 门②（三类证据）：本批**没有新增/修改任何工具**，所以门②的"逐工具成功/缺参/底层失败"不适用；
> 本批的活证据是**跨工具级别的字节证据链**（§4.3：探针 → `save_custom_section` → `ConfigFile` 读回 →
> `InputMap` 读回 → 进程外字节比对），强度高于单工具三类证据。
> 门⑤（`accept_m1` ×2）见 §7.3。

### 7.3 回归电池（门⑤ + 受影响面抽跑 + R-B3）

命令：`powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp056_regression_battery.ps1`
（15 步**严格串行**、每步一个 `powershell -File` 子进程、日志默认 `%TEMP%`）
日志：`%TEMP%\mcp_server_regression\<stamp>\`，控制台副本 `%TEMP%\t058_battery.txt`。**整体退出码 0**。

| 步 | 脚本 | 退出码 | 关键实测 |
|---|---|---|---|
| 1 | `accept_m1_run1` | 0 | `22/22 cases passed`；`implemented tools = 152 (editor) / 72 (game); contract = 175` |
| 2 | `accept_m1_run2` | 0 | **同上**（两次 PASS 清单一致，见下行比较） |
| — | `accept_m1_pass_list_compare` | 0 | 两次清单一致 |
| 3 | `mcp041_gates` | 0 | `STEP regress_mcp040_racing EXIT 0 (46s) | DONE` |
| 4 | `mcp042_gates` | 0 | 同上（46s） |
| 5 | `mcp043_gates` | 0 | 同上（48s） |
| 6 | `mcp010_b2_observation_evidence` | 0 | `phase game: 29/29 checks passed` |
| 7 | `mcp019_b4_evidence` | 0 | `PASS H1_user_editor_port_9877_guard` |
| 8 | `mcp027_object_shape_and_paths_evidence` | 0 | `phase green: 60/60 checks passed`；log sha256 `ed895143…` |
| 9 | `mcp044_capture_evidence` | 0 | `PASS guard_user_port_9877`；`40/40 checks passed (phase editor)` |
| 10 | `mcp045_pixel_compare_cost` | 0 | `15/15 checks passed` |
| 11 | `mcp046_capture_encode_cost` | 0 | `23/23 checks passed` |
| 12 | `mcp050_parameter_guidance_evidence` | 0 | `port 9877 guard : pass=True classification=environment_fact_no_listener_before_or_after`；summary json sha256 `04342152…` |
| 13 | `mcp051_b_tier_evidence` | 0 | 同上 port 9877 guard 通过；summary json sha256 `7a6a05c0…` |
| 14 | `mcp052_added_tools_evidence` | 0 | **53/53 checks passed**；log sha256 `5bd1d530…` |
| 15 | `mcp053_added_tools_evidence` | 0 | **73/73 checks passed**；log sha256 `93ee4350…` |
| — | `tracked_evidence_restored` | 0 | `git diff --stat after=0 line(s); newly modified=0; newly untracked=0; restore failures=0` |
| **整体** | | **0** | `ALL REGRESSION STEPS EXIT 0` |

**TASK-057 任务书列出的"按受影响面抽跑"清单逐条归因**：

| 任务书点名的脚本 | 状态 | 归因 |
|---|---|---|
| `mcp041` / `mcp042` / `mcp043` | **已跑**（电池步 3/4/5，exit 0） | 这三者会重写被跟踪证据 → 正是 R-B3 的受影响面；已还原（§3.3） |
| `mcp010` / `mcp019` / `mcp027` | **已跑**（电池步 6/7/8，exit 0） | 同前；且 `mcp019`/`mcp050`/`mcp051` 的 **9877 用户端口守卫**均通过（本任务**未占用 9877**） |
| `mcp044` / `mcp045` / `mcp046` | **已跑**（电池步 9/10/11，exit 0） | 属"受影响面"清单；全部通过 |
| `mcp050` / `mcp051` / `mcp052` / `mcp053` / `mcp054` / `mcp056` | **其中 050/051/052/053 已跑**（电池步 12/13/14/15，exit 0）；**054/056 未跑** | `mcp054`/`mcp056` 是证据脚本，不在电池 15 步内；它们断言的是 TASK-054/055/056 的既有行为，而本批**未触碰任何工具文件**（§4.2 证据 1），故归因为**不受影响**，见下 `unrun` |
| 门⑤ `accept_m1` ×2 | **已跑**（电池步 1/2，两次 PASS 清单一致） | ✅ |

**"跑不起来 / 没跑"的显式归因**：

1. **`mcp054_forensics_and_csharp_evidence.ps1` / `mcp056_evidence.ps1` 未跑**：
   归因 = **不在 TASK-057 任务书的点名清单**（任务书点名的是 041/042/043、010/019/027、044/045/046、050/051/052/053/054/056——`056` 实为**电池本身** `mcp056_regression_battery.ps1`，**已跑**；`mcp056_evidence.ps1` 与 `mcp054_forensics_and_csharp_evidence.ps1` 未被点名）。
   且本批的 diff **不含任何工具源码**，这两份证据所断言的 TASK-054/055/056 行为不可能受影响。→ 本任务**未跑**，明写在此，**不谎报全绿**。
2. **`mcp044_zero_change.ps1` 未跑**：未点名，且它在 `mcp044_capture_evidence.ps1`（已跑）之外的补充检查。
3. **`DESIGN-DETAIL` 未改**：任务书硬性纪律，**遵守**。

### 7.4 纪律核对

| 纪律 | 实测 |
|---|---|
| 绝不占用/杀/重启 **9877** | ✅ 本任务**从未**在 9877 上起进程；`netstat` 在开工与收尾都**没有** 9877 监听（用户 Godot 当时未运行，属"施工前就无监听者"）；`mcp019`/`mcp050`/`mcp051` 的 9877 守卫全通过，`mcp019` 归类为 `environment_fact_no_listener_before_or_after` |
| 测试端口 **9888/9889** | ✅ 门与电池都绑定 9888/9889；收尾时两者空闲 |
| 禁止 push | ✅ 本任务**没有**任何 push |
| 构建**严格串行**、从 cmd 启动、不抑制输出 | ✅ 本任务**未并发跑任何 scons**（§7.1：本任务未重建，构建已由 TASK-057 完成）；门与电池均从 `cmd` 启动；`mcp057_gates.ps1` 用 `*> $log` **同时**回显并落盘（不抑制） |
| 证据 `curl.exe -s -o` + sha256 | ✅ 脚本内部使用；本报告引用并**独立复算**了关键 sha256（§4.3 字节比对、§7.3 各 log sha256） |
| `.ps1` **纯 ASCII** | ✅ 本任务**未新增/修改任何 `.ps1`**；TASK-057 的 5 个 `.ps1` 文件头均自述 "Pure ASCII on purpose"（本任务目视核对） |
| 只改 `modules/mcp_server/**` 与**必要引擎文件** | ✅ 本任务**只写了本报告**（`docs/reports/`），未改任何源码/脚本/契约 |
| hof-rs 只读 | ✅ 本任务**未触碰** `F:\moonbit-hof-rs` |
| 不得改 `DESIGN-DETAIL` | ✅ **未改** |

---

## 8. 报告提交后的复验（`--version == 新 HEAD`）——**已实跑**

TASK-058 §1.4 要求：报告提交之后再 `build_local.cmd -Force` 复验 `--version == 新 HEAD`。

**本报告第一次提交**：`612829827214e3841f5ebe21439f858db4b72af0`（`--short=9`：`612829827`），
一条提交含 2 个文件（本报告 + TASK-058 任务书），718 insertions、**0 源码改动**。

**随后实测（严格串行、从 `cmd` 启动、不抑制输出、未并发跑第二个 scons）**：

| 步骤 | 命令 | 退出码 | 实测 |
|---|---|---|---|
| 1 | `modules\mcp_server\scripts\build_local.cmd -Force` | **0** | plain `--version` → `4.8.dev.custom_build.612829827` **== HEAD** ✅ |
| 2 | `modules\mcp_server\scripts\mcp057_build_mono.cmd` | **0** | mono `--version` → `4.8.dev.mono.custom_build.612829827` **== HEAD** ✅ |
| 3 | `bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="[MCPServer]*"` | **0** | `test cases: 332 \| 332 passed \| 0 failed`；`assertions: 23625 \| 23625 passed \| 0 failed`；`Status: SUCCESS!` |

**为什么连 mono 也重建**：本报告提交推进了 HEAD（`96f631add` → `612829827`），
若只重建 plain，mono 会**落后一个（纯文档）提交**。那会让 `mcp052`/`mcp053` 的 `engines_match_head`
在下一批出现**假红**——D-B1 当初的症状正是"mono 与 HEAD 不符"。**症状相同、原因不同，从输出上无法区分**
（旧 mono 自报 `96f631add`，与"代码陈旧"的 `4e3de1090` 相比只是"落后一个文档提交"）。
因此把 mono 一并重建，使两个变体都锚在新 HEAD 上；代价是两次重建的墙钟时间，收益是消除 D-B1 同形假红。

**改动范围**：报告提交只含文档，故"报告提交"这一提交**不改变任何被编译的字节**；
两次重建的差异仅在于 `core/version_generated.gen.h` 里的短哈希与 `--version` 文本。
plain 重建后门③ 仍 `332/332`，证明重建产物可用（不是只"能链接"）。

**收尾工作树**：仍只剩既有未跟踪物 **4 个**（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`）。

> **本报告后续若有 amend/追加提交**（例如补上本节），报告文件自身的 sha256 会随之变化；
> §0 里**被改动的 12 个源文件/脚本**的 sha256 **不受影响**（它们在本任务中从未被改写）。
> 本报告**第一次提交**时的 sha256 为 `1da69815294e6b11105e3b16c07062fe89309413291c8f91935964566f55bcd6`（47347 B，UTF-8 无 BOM，683 行）。

### 8.1 关于「本报告自身的追加提交」与二进制锚点的关系（**明确记录，避免误判**）

本节的追加是以**第二条提交** `9058e41d82`（`--short=9`：`9058e41d8`）进入历史的。
该提交**只改了本报告一个文件**（`1 file changed, 36 insertions(+), 20 deletions(-)`），**0 源码改动**。
因此：

- 两个二进制仍自报 `612829827`，而当前 HEAD 是 `9058e41d8` —— **二者相差一个纯文档提交**。
- 这**不是** D-B1 那种缺陷：D-B1 要求"二进制包含**当次代码**的哈希"，
  而 `612829827 → 9058e41d8` 之间**没有任何被编译的字节变化**，二进制是**源码等价**的。
- 若下一批的门要求 `--version` 严格等于当时的 HEAD，只需先
  `modules\mcp_server\scripts\build_local.cmd -Force` →（mono 需要时）`mcp057_build_mono.cmd`，
  **串行**重建即可；本任务**不**为"补齐一个纯文档提交的哈希"再烧一次两次全量重建。
- **D-B1 的实质要求（二进制由当前**代码**构建）已经满足**：`612829827` 的树与 `9058e41d8` 的树，
  在一切**非文档**文件上逐字节相同。

---

## 9. `deviations`（与手册/任务书的偏离，逐条显式列出）

1. **门的运行没有重建二进制**：论证见 §7.1 —— 跑门时两个二进制已自报 HEAD `96f631add`，
   门脚本自己在开头断言了这件事。**报告提交之后**按 §8 做了两次重建（plain + mono）复验 `--version`，
   故"每批开跑门之前重建"的纪律在本任务的**门阶段**是由"二进制已锚在 HEAD"满足的，而不是由本任务重建满足的。
2. **报告路径采用 TASK-058 §1.4 指定的 `…-settings-publish.md`**，而非 TASK-057 任务书标题的
   `…-project-settings-publish.md`（TASK-057 自身矛盾，缺陷 D-6）。
3. **未跑 `mcp054_forensics_and_csharp_evidence.ps1` / `mcp056_evidence.ps1` / `mcp044_zero_change.ps1`**：
   归因见 §7.3"跑不起来/没跑"。
4. **未伪造红阶段 doctest 输出**（D-3）：TASK-057 未留红证据，本任务用独立活证据补强，不编造。
5. **未修改 TASK-057 已提交的证据脚本**（D-1/D-2）：只在报告里报缺陷，保持"报告 ↔ 提交脚本"一致。

## 10. `blockers`

**无阻塞项。** 本任务四件事全部核实通过，门与回归全部实跑并退出 0。
需要**决策者裁决**的只有规范层事项：D-6（报告路径唯一化）与 D-4（是否把 5 个工具切到新路径并同步改描述）。

## 11. `next_step_recommendation`

1. **裁定 D-6**：把 TASK-057 任务书标题的统一路径定下来（建议就用本报告的路径）。
2. **另批切换 5 个工具到新路径**（`project_set_setting`、`editor_add_input_action`、
   `project_add_autoload`/`project_remove_autoload`、以及第 787 行那个工具）：
   这是 TASK-057 §4④ 预留的"另批"动作。该批**必须**：①单列「行为变更」；②同步更新 5 条契约描述
   （去掉 "the engine has no partial-publish API"）；③为"注释不再丢失"补一组**新的**活证据；
   ④注意契约 sha 与文档指纹会变（`_meta.map_sha256` 若受影响需同步）。
3. **修 D-1/D-2**（证据脚本的两处自证缺陷）：小改动、低风险，可在上述批次里顺带完成。
4. **可选**：给 `mcp057_build_mono.cmd` 加 `SCONS` 环境变量覆盖（消 D-5）；把引擎侧窄化点纳入
   某份"引擎侧窄化清单"（消 §5 的边界缺口）。

---

## 附：本任务使用/产生的证据路径

| 内容 | 路径 |
|---|---|
| 门控制台日志（15 步，全 0） | `%TEMP%\t058_gates_console.txt`（副本 `%TEMP%\t058\gates_console.txt`） |
| 门分步日志 + 汇总 | `%TEMP%\mcp057\gates\20260925-031043\`（`summary.txt` 等 15 份） |
| 回归电池控制台日志（全 0） | `%TEMP%\t058_battery.txt`（副本 `%TEMP%\t058\battery_console.txt`） |
| 回归电池分步日志 / R-B3 清单 | `%TEMP%\mcp_server_regression\<stamp>\`（含 `restore_manifest.txt`、`git_status_short_{before,after}.txt`、`git_diff_stat_{before,after}.txt`） |
| 补丁 2 字节证据 | `%TEMP%\mcp057\settings-publish\20260925-031420\`（`summary.txt`、`logs\lf_{actual,expected}.godot` 各 409 B，sha256 `5453ba95…`） |
| `mcp052` 证据 | `%TEMP%\mcp052\evidence`，log sha256 `5bd1d530ef994121629de895cd5f20d67dbfd30c9c77e9233eda75701b17ab7b` |
| `mcp053` 证据 | `%TEMP%\mcp053\evidence`，log sha256 `93ee4350956239bf537aa0b1c0ad949115cc4d564600b23d4231531e7ef3b06c` |
| 门⑥ 探针日志 | `%TEMP%\task031-gate6-probes\logs`，log sha256 `a1515e0a465f0c910e34580b4fb66764a81218701b34ad37411a501f059a64d8` |
| 报告提交后的重建日志（§8） | plain：`%TEMP%\t058_build_plain.txt` + `%TEMP%\mcp_server_build_local.log`；mono：`%TEMP%\t058_build_mono.txt` + `%TEMP%\mcp057\mono_build.log`（两次 exit code 均 0） |
| 重建后冒烟（§8） | `%TEMP%\t058_smoke.txt`（`--headless --test --test-case="[MCPServer]*"` → 332/332，exit 0） |

**返回决策者（≤10 行）见提交说明与 §7 汇总。**