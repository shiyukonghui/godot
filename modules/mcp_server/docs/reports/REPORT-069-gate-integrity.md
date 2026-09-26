# REPORT-069 — 两条门缺陷：回归电池**删证据** + 门**内红却 exit 0**

> 任务书：`docs/tasks/TASK-069-gate-integrity.md`；手册：`docs/tasks/PLAYBOOK-group-port.md`。
> 来源：`REPORT-068-registered-items.md` §5.4 的两条实测（门⑤ 段落）。本报告的全部结论只在下表锚点上成立（D86）。

## 0. 元信息与锚点（D86）

| 项 | 值 |
|---|---|
| 角色 / 任务 | 实现工程师 / TASK-069 |
| 状态 | **完成**：两条门缺陷都**先复现、后修、再验证**；3 处陈旧期望改成派生并过反向探针；普查点名 **14** 个同类脚本（**12 修 / 2 pin 带理由**）；新增仓库内断言并**接进 `accept_m1.ps1`**；最终回归电池 **17/17 步 exit 0**、`accept_m1` ×2 = **23/23** 清单一致；无阻塞 |
| **工作树锚点** | `git rev-parse HEAD` = **`48a3c2e33c0b46bc253e6a0c0cb836a462552954`**（`--short=9` = `48a3c2e33`）。本批**未提交**（父层决定）；交付时工作树 = HEAD + **17 个 ` M `** + 本批新增文件（5 个脚本 + 报告 + 证据树 + 任务书），植入样例报告已在交付前删除（§7.3） |
| **二进制锚点** | plain `bin\godot.windows.editor.x86_64.console.exe` = `4.8.dev.custom_build.48a3c2e33`；mono `bin\godot.windows.editor.x86_64.mono.console.exe` = `4.8.dev.mono.custom_build.48a3c2e33`。**两者都 `--version == HEAD`**；构建严格串行（§5.1） |
| **契约** | `docs/tools_list.renamed.json` = **`701539829ed8fcaa227f280fb6bff71b96522248cd9c4b84f2073c27eb17cfe0`**（155872 B，条数 **176**）——**本批一个字都没动**（与 TASK-068 的锚点逐字节相同，§5.5）；本批只改脚本 |
| **端口纪律** | 9877 全程只用 `mcp_port_guard.ps1` 分类观测；只用 9888/9889；只 stop 本脚本 `Start-Process` 的 PID；**未占用、未杀、未重启 9877** |
| **禁止 push** | 未 push；未做任何提交 |
| **构建纪律** | 从 **cmd** 启动；全程**只有一个 scons**；`build_local.cmd` / `mcp057_build_mono.cmd` 自己把 scons 输出重定向到 `%TEMP%` 日志（不抑制、不经管道）；plain → mono 严格串行 |
| **`.ps1` 纯 ASCII** | 本批新增的 4 个 `.ps1` 全部纯 ASCII（机器核验：`non-ascii-bytes=0`）；新增的 2 个 `.py` 亦为纯 ASCII。改动的 `.ps1` 也全部复核为纯 ASCII |
| **红相位输出当场保存** | `docs\reports\evidence\task069\logs\prefix_mcp042_gate2.log`、`...\prefix_mcp043_gate2a.log`（两条缺陷的复现原始输出，改动前落盘） |
| **证据前缀（绝对路径）** | `F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task069\` |
| **改动文件（17 个 ` M `，+499 / −42）** | `scripts/mcp_evidence_guard.ps1`、`scripts/mcp056_regression_battery.ps1`、`scripts/accept_m1.ps1`、`scripts/{mcp041,mcp042,mcp043}_gates.ps1`、`scripts/mcp042_projectrewrite_and_honesty_evidence.ps1`、`scripts/mcp043_description_evidence.ps1`、`scripts/{mcp050,mcp051}_regression_battery.ps1`、`scripts/mcp051_gates.ps1`、`scripts/mcp051_gate1_groups.ps1`、`scripts/mcp022_unified_narrowing_gate_evidence.ps1`、`scripts/mcp023_narrowing_guardrail_evidence.ps1`、`scripts/{mcp040_defect_probes,mcp040_racing_regression}.ps1`、`docs/scripts/selfcheck.py`（§5.8 的 `git diff --stat` 逐字） |
| **新增文件** | `scripts/check_exit_propagation.py`、`scripts/mcp069_override_dump.py`、`scripts/mcp069_guard_whitelist_probe.ps1`、`scripts/mcp069_exit_propagation_demo.ps1`、`scripts/mcp069_stale_expectation_reverse_probe.ps1`、`docs/reports/REPORT-069-gate-integrity.md`（+ `docs/reports/evidence/task069/**`、任务书本身） |
| **只允许改 `modules/mcp_server/**`** | 本批**没有**改任何引擎文件；hof-rs **只读**（`DECISIONS.md` 由决策者维护，本批**未写**）；`docs/DESIGN-DETAIL.md` **未改**；**未 push** |

---

## 0.1 一句话结论

| # | 任务书要求 | 结论 | 关键数字 |
|---|---|---|---|
| ① | 电池删未跟踪报告 → 先复现 → 只允许改自己声明的产物（路径白名单 + 默认拒绝） | **已修**：`Restore-McpEvidence` 增加 `-AllowedPaths` / `-AllowedRoots`，**默认拒绝**；未声明的路径打印 `UNTOUCHED` 后**一个字节都不动** | 复现：电池清单逐字 `REMOVED modules/mcp_server/docs/reports/REPORT-069-planted-untracked-during-PRE.md` + `newly untracked=0`；修复后 **RESTORED-NEW 1 / REMOVED 0 / untouched 1**，植入文件 sha256 前后一致 |
| ② | `mcp041/042/043_gates` exit 0 掩盖内红 → 内红则非零 + 修 3 处陈旧期望 + 普查 + 新增仓库内断言 | **已修**：三个驱动加**同一段收口**（读自己的 summary，任何 `EXIT [1-9]` → `exit 1`）；A22/A23/A26b 与 L21×5 改**派生**；普查**点名 14 个**同类脚本（**12 修 / 2 pin 带理由**，其余机器核验已正确传播）；新增 `check_exit_propagation.py`（门⑥ 形状）并**接进 `accept_m1.ps1` 的 `case0`** | 复现：`mcp042_gates | 0` 而其内 `STEP gate2_rewrite_and_honesty_evidence EXIT 1`、`30 checks, 3 failed`；`mcp043_gates | 0` 而其内 `gate2a…EXIT 1` / `gate2d…EXIT 1`。修复后三个驱动 `ALL STEPS EXIT 0`；人为制造一红 → `mcp042_gates` exit **1** |
同样先放 `…-before-POST.md`（sha256 `73364b8a…`），**运行中**再放 `…-during-POST.md`（sha256 `65980694…`）。电池清单（逐字）：

```
RESTORED-NEW modules/mcp_server/docs/reports/evidence/task051/red/e20_child_status.json
UNTOUCHED modules/mcp_server/docs/reports/REPORT-069-planted-untracked-during-POST.md
SUMMARY restored=55 removed=1 kept-dirty-before=16 untouched=1 (declared paths only; undeclared paths are never touched)
```

清单里**没有任何 `REMOVED` 行**（旧词汇已不存在），`RESTORE-FAILED` = 0。运行后实测（Test-Path + sha256 前后一致）：

```
before-POST exists=True sha256=73364b8a550c5d5a3327576a1d126c9a00f1db67336c7c4ca5868f3dfbf107de（= 植入值）
during-POST exists=True sha256=65980694dbb3a4be547344ac32fd05b42e7f54ea17629dfd405cef3296cbe886（= 植入值）
before-PRE  exists=True sha256=4a2ce4ab24e6a5e9a719266916bb2e6afe5f4f9301430788201dfd850e5410b5（= 植入值）
```

电池收口（逐字）：`tracked_evidence_restored|0|declared leftovers=0 (every declared artifact is back); undeclared paths left alone=1; restore failures=0; git diff --stat after=17 line(s)`。

**同一场景的 `git status` 前后对照**（电池自己落的快照，逐字在 `evidence/task069/battery_*/git_status_short_{before,after}.txt`；每轮电池在**第一个步骤之前**与**还原之后**各写一份）：

```
PRE   before : ?? modules/mcp_server/docs/reports/REPORT-069-planted-untracked-before-PRE.md
               （during-PRE 尚未创建 -> 它不在 before 快照里，所以落在差集）
PRE   after  : ?? modules/mcp_server/docs/reports/REPORT-069-planted-untracked-before-PRE.md
               （during-PRE 已不在 -> 被删；before-PRE 仍在）
FINAL after  : ?? modules/mcp_server/docs/reports/REPORT-069-planted-untracked-before-FINAL.md
               ?? modules/mcp_server/docs/reports/REPORT-069-planted-untracked-during-FINAL.md
               ?? ...（before-PRE / before-POST / during-POST 也都在）
               （during-FINAL 仍在 -> 未被触碰）
```

`git status --ignored` 的交付态快照：`evidence/task069/git_status_ignored_after_cleanup.txt`（植入样例清理之后）。

**两次清单的逐对比就是「同一场景文件仍在」的证据**：PRE 的 `REMOVED …during-PRE.md` ↔ POST/FINAL 的 `UNTOUCHED …during-{POST,FINAL}.md`（同为「运行中写入的未跟踪报告」，一边被删、一边被如实列为「未触碰」）。

### 1.6 验证二：反例 + 默认拒绝 + 语法本身（`mcp069_guard_whitelist_probe.ps1`，19/19 PASS）

在 `%TEMP%` 的**临时 git 仓库**上直接压 `Restore-McpEvidence`（仓库文件零写入），四个路径同时在场，逼声明**做区分**而不是「一律不动」：

```
manifest (scenario A: -AllowedRoots evidence)
    UNTOUCHED-MODIFIED docs/reports/other.txt      <- 声明外、被改：不动
    RESTORED evidence/tracked.txt                  <- 声明内、被改：还原到 HEAD
    UNTOUCHED docs/reports/REPORT-planted.md       <- 声明外、新增：不动（sha256 不变）
    RESTORED-NEW evidence/new_declared.json        <- 声明内、新增：删除