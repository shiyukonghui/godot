# REPORT-062 — 回收第 2 轮试测产物（落错目录）+ 补做缺失的 §D 汇总

- **status**：完成（①回收 ✅ / ②诚实标注 ✅ / ③补做 §D 汇总 ✅）
- **分支**：`feature/mcp-server-module`
- **起始 HEAD**：`97144b5afb`
- **本批提交**：`f6f2ff3376`（537 个文件，全部在 `modules/mcp_server/docs/**` 内）
- **被回收产物的写作锚点（D86）**：`4f99a4e37ac4160b5c9b98513068872521bee975`
- **返回决策者**：≤8 行总结 + 报告路径（见文末）

---

## 0. 一句话结论

根 `docs/reports/**` 的 **445 个文件 / 658 190 B** 已整体搬入
`modules/mcp_server/docs/reports/**`，**搬前搬后 sha256 清单逐字节相同（0 差异）**；
6 个文件里的根 `docs/` 路径引用已改指新位置，3 份产物头部已前插状态声明（正文未改）。
此外从 `%TEMP%\mcp-breakout` **额外回收了 78 个原始追踪/日志/脚本证据**（含 §B 曾承诺但从未入库的
`run.log`），并据此**补做出了 TASK-060 §D 从未产出的汇总**：
`modules/mcp_server/docs/reports/BREAKOUT-FINDINGS.md`。
**六条新能力判据的结论是 ①不通过 / ②通过 / ③通过 / ④不通过 / ⑤不通过(未构造) / ⑥不通过(未构造)。**

---

## 1. ① 回收

### 1.1 搬移

| 项 | 值 |
|---|---|
| 源 | `F:\RustProjects\godot-mcp-pro\code\godot\docs\reports\`（引擎仓根，**未跟踪**） |
| 目标 | `modules\mcp_server\docs\reports\`（已跟踪目录，合并） |
| 方式 | 逐顶层项 `Move-Item`。**注意**：目标**已存在** `evidence/`（内含 `racing`、`task040…task061`），所以 `docs/reports/evidence/task060` 是单独搬进 `target/evidence/task060` 的——**没有覆盖任何既有证据**（`task060` 在目标下原本不存在，已核对） |
| 收尾 | 根 `docs/` 只剩空目录 → `Remove-Item -Recurse -Force`；`Test-Path docs` = **False** |

### 1.2 搬前/搬后对照（证明没有丢内容）

| 项 | 搬前 | 搬后 |
|---|---|---|
| 文件数 | **445** | **445** |
| 总字节 | **658 190** | **658 190** |
| 清单文件 | `recovery/MOVE-BEFORE.sha256.tsv` | `recovery/MOVE-AFTER.sha256.tsv` |
| 清单自身 sha256 | `a7a623a5417e44fbe0fe9a779e9de117d2bd9ee3d5313a6ad3572b021c29f7ce` | `a7a623a5417e44fbe0fe9a779e9de117d2bd9ee3d5313a6ad3572b021c29f7ce` |
| `Compare-Object` 差异条数 | — | **0** |

> 清单格式：`<目标根相对路径>` TAB `<字节数>` TAB `<sha256>`，**两条清单同格式**，
> 所以「0 差异」等价于「每个文件的字节数与内容哈希在搬移前后完全相同」。
> 逐行文本摘要另见 `recovery/MOVE-COMPARISON.txt`。

### 1.3 修正被搬文件内的路径引用

**规则（单一、可审计）**：凡**未被 `modules/mcp_server/` 前缀保护**的裸 `docs/` 或 `docs\`
前缀 → 改写为 `modules/mcp_server/docs/`；凡绝对路径里的 `code\godot\docs\` /
`code/godot/docs/` → 改写为 `code\godot\modules\mcp_server\docs\`。**仅做字符串替换，不改语义。**

| 文件 | 旧 sha256（搬后/改前） | 新 sha256（改后） | 字节 | 处数 |
|---|---|---|---|---|
| `BREAKOUT-TEST-PLAN.md` | `127a85ae91a5688746ebd52e5a2ad831b08d828b5f1eda28d1e890b1e391cd05` | `fec1da6d68d82933093f4a7e28eff407b3a4dc8343495fb1a4e2317ce326fa5d` | 61 191 → 61 362 | 9 |
| `BREAKOUT-DEV-LOG.md` | `4b44b158a20713e97369485845023643f0b22ca35647dc53f8b9da0d56df56b7` | `8fcba156b37caaee711b47046350256cc4c2979d9dec0cf0a8f2c8cff052f491` | 31 983 → 32 078 | 5 |
| `BREAKOUT-OBSERVATIONS.md` | `100ab5c5d4e215c3ad0a3f5a5d8ad21d7b80155bf476c0e82839c04bd5105e07` | `3da18b88ee20b624097b49034e08f2888b84aa53ea57235038fccc25ccfbccf2` | 28 935 → 29 011 | 4 |
| `evidence/task060/PROVENANCE.json` | `f04d3a7ad748041e4935ceef8c041785c4e7fefec9c2dcc2bbb5e8a535f387ee` | `066f3ac137207e52267fb5898bd24b92fe9b21f51976c6aa021ef9faad3e23d5` | 5 878 → 5 973 | 5 |
| `evidence/task060/c-obs/analyze-final.json` | `c9893a4f56cae894efb2897aba5730c904e58d44c5f03704e7432404ce11d859` | `d2d47c47cf776e9814ce781d43243c9ebb3e2e2a853ff7303c1d06612dc2dc26` | 3 291 → 3 312 | 1 |
| `evidence/task060/c-obs/watch.ps1` | `21c99ce28aa83e02c7a8231811e4eaf3e2dec921225da7946adab1021faa23ba` | `a18e9c052d087ec2544c3dff4794261c505bf89573c918e35d44b667cbc84d8c` | 2 021 → 2 040 | 1 |

机器可读对照：`recovery/PATHFIX-TRANSFORM.tsv`。

**自检（全部通过）**：
- 每个文件的增量都是 **19 字节 × 处数**（`modules/mcp_server/` 恰好 19 字符）
  → **没有多余改写**，逐文件字节账目对得上。
- 全树复查：**已无任何未受保护的裸 `docs/` 或 `docs\` 引用**。
- 3 份 JSON 用 UTF-8 感知方式 `ConvertFrom-Json` 复核：**全部通过**。
- `watch.ps1` **仍是纯 ASCII**（`>127` 的字节数 = 0）。
- 3 份 Markdown 与 `watch.ps1`：**BOM 状态不变（均无 BOM）**；`analyze-final.json` 原有的
  125 个 CR 字节**前后一致**；其余文件均 LF-only。

> **过程中的一次自纠（如实记录）**：`analyze-final.json` 里的路径是 **JSON 转义形式**（`docs\\reports\\`），
> 第一遍替换只处理了单个反斜杠，产出了非法转义 `\m`。**当场发现**（`ConvertFrom-Json` 报
> `Unrecognized escape sequence`），已改为 JSON 转义形式并重新校验通过。
> 该文件在 `PATHFIX-TRANSFORM.tsv` 里记录的「新 sha256」是**修复后**的值。

### 1.4 `PROVENANCE.json` 的哈希口径（显式声明，不悄悄改）

`PROVENANCE.json` 记 `artifact.sha256 = 127a85ae91a5688746ebd52e5a2ad831b08d828b5f1eda28d1e890b1e391cd05`
（指 `BREAKOUT-TEST-PLAN.md`）。该值经复核**对搬移后的原文件仍然成立**
（= `PATHFIX-TRANSFORM.tsv` 里该文件的「旧 sha256」）——也就是说 §A 的溯源记录**当时是准确的**。
TASK-062 **刻意不重算**这个字段（重算会毁掉溯源记录本身）；该文件「改路径引用后」与「前插标注后」的哈希
分别在 `PATHFIX-TRANSFORM.tsv` 与 `ANNOTATION-TRANSFORM.tsv` / `POST-RECOVERY-MANIFEST.sha256.tsv` 里。
同理，`BREAKOUT-OBSERVATIONS.md` §7 的 13 行 sha256 表里 **11 行仍逐字节成立**，
不符的 2 行恰好就是本次改过的那两个文件（`watch.ps1` / `analyze-final.json`）。

### 1.5 入库后的 EOL 归一化声明（诚实交代，因为它影响「从提交复算 sha256」）

本仓库根的 `.gitattributes` 有一条**仓库级、既有**规则 `* text=auto eol=lf`（上游 Godot 自带），
本机另有 `core.autocrlf = true`。因此**含 CRLF 的文本文件写进 git 对象时会被归一化成 LF**。
TASK-062 实测（在本批 535 个即将入库的文件上）：

| 类别 | 文件数 | 说明 |
|---|---|---|
| 工作树无 CR → 提交对象与工作树**逐字节相同** | **508** | 含**全部** `c1`–`c4` 的请求/响应原文与 `.sha256` 边车、3 份 `BREAKOUT-*.md`、以及 TASK-062 自己的全部产物（已刻意写成 LF） |
| 有 CR | **27** | —— |
| ├ 孤立 `\r`（进度条，非换行）→ 仍**逐字节相同** | **6** | 4 个 `*.log` + 2 个导入日志 |
| └ CRLF → 提交对象归一化为 LF，**字节数与 sha256 都变** | **21** | 见下表 |

**21 个被归一化的文件**（`worktree_sha256` = 回收现场原始字节；`committed_blob_sha256` = git 对象里真正存的）：

| 文件 | 原 CR 数 | 工作树 sha256 | 入库 blob sha256 |
|---|---|---|---|
| `DEV-LOG-raw-run.log` | 281 | `e8ac551b8c4e…` | `3638c5340291…` |
| `c-obs/analyze-final.json` | 125 | `d2d47c47cf77…` | `bd2aeed404a3…` |
| `c-obs/watch.log` | 77 | `a584bc61dcfc…` | `a23a50b6685d…` |
| `c-obs/editor-headless.out.log` / `trace-recovered/logs/editor-headless.out.log` | 27 | `0c20ec332089…` | `bdf9cbef5cc6…` |
| `c-obs/run.log` | 6 | `3faf1c8b9dd4…` | `3b67b10a0483…` |
| `trace-recovered/logs/{import-noflag,import-p9889}.log` | 26 | `023a993c2ebd…` / `2da83848971a…` | `e877d84636e9…` / `8ca83a3f6176…` |
| `trace-recovered/logs/{game.out,game.err,restart.out}.log` | 9 / 2 / 2 | `0cbaab94aea0…` / `b3c95a3b3f1d…` / `76677eaca814…` | `3cf47c23d215…` / `029c429a32c4…` / `2da2928823d7…` |
| `trace-recovered/out/*.out.txt`（10 个） | 33…109 | 见 `GIT-EOL-NORMALIZATION.tsv` | 见同表 |

- **完整机器可读对照**：`recovery/GIT-EOL-NORMALIZATION.tsv`（27 行，含 `identical` 列）；
  说明：`recovery/GIT-EOL-NORMALIZATION.md`。
- **要点**：`c1`–`c4` 的证据**全部属于「无 CR」一类**，所以「`.sha256` 边车 ↔ 响应文件」的自校验
  **在任何一次干净 clone 后依然成立**（TASK-062 实测 **127/127 相符**）。
- **为什么不去改 `.gitattributes`**：那是仓库级既有政策，超出「本批只动 `docs/**`」的授权。
  若要逐字节保真，应**单独一批**给 `docs/reports/evidence/**` 加 `-text` 并独立决策。

---

## 2. ② 诚实标注

在**三份产物头部前插**了状态声明（**原正文一字未改**，只是前插 + 一个空行）：

| 文件 | 字节 | CR（前/后） | 说明 |
|---|---|---|---|
| `BREAKOUT-TEST-PLAN.md` | 61 362 → 63 250 | 0 / 0 | 5 点声明 |
| `BREAKOUT-DEV-LOG.md` | 32 078 → 34 304 | 0 / 0 | 5 点声明（额外点明 §4.4/§4.5/§4.6/§4.7 仍是占位符） |
| `BREAKOUT-OBSERVATIONS.md` | 29 011 → 31 481 | 0 / 0 | 5 点声明（额外点明「零工具调用」只对 06:00:25 之前成立） |

机器可读对照：`recovery/ANNOTATION-TRANSFORM.tsv`。三点硬要求都写了：
1. **本轮 workflow 被取消**，产物是**中断时的快照**；
2. **观察者使用旧协议（TASK-061 之前）**，观察在开发结束前停止，`BREAKOUT-OBSERVATIONS.md` 覆盖**不完整**；
3. **不得把这些快照当完整记录使用**（并指明以 `BREAKOUT-FINDINGS.md` 为准）。

---

## 3. ③ 补做 §D 汇总

**产物**：`modules/mcp_server/docs/reports/BREAKOUT-FINDINGS.md`

- **以 `evidence/task060/**` 原文为准**，全程不采信 §A/§B/§C 的叙述；对不上的**逐条纠错（§4，10 条）**。
- **六条新能力判据**（每条 = 判据编号 / 结论 / 证据文件 + sha256）：

  | # | 能力 | 结论 |
  |---|---|---|
  | ① | 注释保全 | **不通过**（4 条子判据通过；**P1c 判据自相矛盾**；**P1f 与证据相反**——`p1_report.txt` 说 InputMap 有 `mcp060_probe_action`，其引用的响应原文里没有） |
  | ② | C# 真结论（`invalid`+编译器原文 / `ok` / `not_compiled`） | **通过**（含「同一响应里 `invalid` 与 `not_compiled` 并存」的最强证据复现） |
  | ③ | 批量父子（`resolve_within_batch`） | **通过**（`count=26`——方案写 27 是**方案缺陷**） |
  | ④ | 批量挂脚本含 `keep_existing` | **不通过**（跳过语义通过，但**读回证明不可归因**、**「跳过不动盘」是退化对照**、`P4f` 未构造） |
  | ⑤ | `scope` 收窄 | **不通过（未构造）**：全程 **0 次**调用该工具 |
  | ⑥ | 捕获 `changed:false` | **不通过（未构造）**：**307/307 捕获行是 `unavailable` / `changed:null`**，无窗口化进程 |

- **四张表**（每条带证据 + 强度 + 影响面 + 建议/不建议）：
  **异常 7 条** · **缺失工具 5 条** · **可合并候选 5 条** · **可优化 6 条**。
- **疑似缺陷单列 10 条**：每条给最小复现 + 期望/实际 + 证据 sha256 + 严重度，
  并按 `[产品]` / `[试测产物-流程]` **分类**（后者同样要修，否则下一轮还会错）。
- **观察完整性**：§0.3 逐项对账 `stop_reason`（**`BUDGET_REACHED`，非 `marker`**；无 `watch-summary.json`），
  §5 **逐条列清哪些结论受影响 / 哪些不受影响 / 哪些仍是空白**。

**复算口径（可复现）**：25 份追踪按 **`(pid, seq)`** 去重（`seq` 每代重启、`trace_opened` 是唯一分代边界）
⇒ **309 次 `tools/call`、28 代、307 条捕获行**；错误码 `0`×200 / `-32602`×77 / `-32001`×22 / `-32000`×7 / `-32601`×3；
失败→成功对 28 对。产物：`trace-recovered/TRACE-FRICTION-ANALYSIS.json`、`TRACE-RECOVERY-SUMMARY.json`。

---

## 4. 计划外的必要回收（`%TEMP%` 原始追踪）——**这是本批能做出 §D 的前提**

TASK-060 §D 的输入要求是「两份追踪原文（**仓库内副本**）」，但回收发现：
**仓库里只有观察者那 6 行追踪**，开发 06:26–08:01 的追踪**从未入库**。
现场核对 `%TEMP%\mcp-breakout` 仍然完整存在（只读复制，**没有修改 scratch 工程**），因此补回收：

| 目录 | 内容 | 文件数 |
|---|---|---|
| `evidence/task060/trace-recovered/` | 最终编辑器追踪（82 992 B）+ 24 份 `.prev-*` 快照 + 游戏追踪 | 26 |
| `…/trace-recovered/prev/` 已含在上行 | —— | —— |
| `…/trace-recovered/logs/` | 编辑器/游戏 `.out.log`/`.err.log`、导入日志、重启日志 | 10 |
| `…/trace-recovered/scripts/` | 开发者自备的 25 个 `mcp060_*.ps1`（含**从未跑过**的 `c5`/`c6` 脚本） | 25 |
| `…/trace-recovered/out/` | `*.out.txt` 运行输出、pid、就绪探针 | 16 |
| **`evidence/task060/DEV-LOG-raw-run.log`** | **`run.log`（41 159 B）**——§B 在 `BREAKOUT-DEV-LOG.md` §2 承诺过「仓库内副本」但从未入库的那一份 | 1 |
| 合计 | sha256 清单：`trace-recovered/TRACE-RECOVERY-MANIFEST.sha256.tsv` | **78**（555 086 B） |

**这三条独立证据就是本批最关键的发现来源**：
- `trace-game.jsonl` + `logs/game.out.log` → 游戏端点 **`bind failed (error=22)` / `get_port()=0`**（§3 D-7）；
- 25 份追踪 → **0 次 `editor_list_signal_connections` 调用、0 条 `changed:true/false`**（⑤⑥ 的判据）；
- `run.log` → **同名证据文件被复用覆盖**，这正是构建表对不上账的根因（§3 D-4）。

> **`.gitignore` 陷阱（TASK-061 已登记）**：`*.log` 被忽略，**必须 `git add -f`**。
> 本批共 **8 个**被忽略的路径**已被 `git add -f`**：`DEV-LOG-raw-run.log`、
> `b0-bootstrap/{import.log,import-attempt.log,import-full.log}`、
> `c-obs/{watch.log,run.log,editor-headless.out.log}`、`trace-recovered/logs/`（整目录）。

---

## 5. 门与纪律

| 要求 | 实况 | 判定 |
|---|---|---|
| `git diff --stat -- modules/mcp_server/tools tests` **必须为空** | 输出为空（exit 0） | ✅ **PASS** |
| 契约不动 | `git status --porcelain -- …/tools_list.renamed.json …/tool-rename-map.json …/tool-groups.json` 为空 | ✅ **PASS** |
| 只动 `docs/**`（必要时 `scripts/**`） | 本批**没有**改任何 `scripts/**`；改动全部落在 `modules/mcp_server/docs/**` | ✅ |
| **绝不占用/杀/重启 9877** | 本批**没有启动任何 Godot 进程**，没有监听/绑定任何端口；全程只读文件与只跑 Python/PowerShell 分析脚本 | ✅ |
| 禁止 push | 只做本地提交 | ✅ |
| `.ps1` 纯 ASCII | 本批**新建的 `.ps1` 都在 `%TEMP%`**（不入库）；入库的 `watch.ps1` 经复核 `>127` 字节数 = **0** | ✅ |
| `*.log` 被 `.gitignore` 挡住要 `git add -f` | 8 个被忽略路径已 `-f` 加入 | ✅ |
| 结论按 **D86** 标锚点 | 本报告与 `BREAKOUT-FINDINGS.md` 均标 `4f99a4e3…`（被评产物）/ `97144b5afb`（回收动作） | ✅ |
| 不伪造输出 | 所有数字均来自落盘文件；命令输出原文可复算（`MOVE-*.tsv`、`TRACE-*.json`、`PATHFIX-TRANSFORM.tsv`、`ANNOTATION-TRANSFORM.tsv`、`POST-RECOVERY-MANIFEST.sha256.tsv`） | ✅ |

**收尾自检（实测）**：
- 工作树只剩**既有**未跟踪物（`.graphifyignore`、`build-m0.cmd`、`install-deps-m0.cmd`、`graphify-out/`）
  与本批新增的 `modules/mcp_server/docs/**` 条目。
- 回收后证据树 + 4 份 `BREAKOUT-*.md` 的**全量** sha256 清单：
  `recovery/POST-RECOVERY-MANIFEST.sha256.tsv`（**527 行**）。
- 本轮**没有**修改 `modules/mcp_server/tools/**`、`tests/**`、`modules/mono/**` 或任何生成器。

---

## 6. `deviations`（与任务书的偏离，逐条显式列出）

| # | 偏离 | 理由 |
|---|---|---|
| **V-1** | **超出 §1.1 的范围，从 `%TEMP%\mcp-breakout` 额外回收了 78 个文件**（§4） | 任务书 §1.3 要求「**以 `evidence/task060/**` 的原文为准**」，而当时 `evidence/task060` **没有**开发期的追踪原文——不补回收就**无法**按原文答 ⑤⑥ 与四张表，只能照抄报告叙述（正是任务书禁止的）。补回收是**只读复制**，不改 scratch 工程 |
| **V-2** | 额外产出 `recovery/TASK-062-TOUCHED-FILES.md`、`MOVE-COMPARISON.txt`、`POST-RECOVERY-MANIFEST.sha256.tsv`、两个 `TRACE-*.json` | 任务书要求「给搬前/搬后 sha256 对照」「证明没丢内容」；把这些做成**机器可读**文件，比只写在报告里更可核对 |
| **V-3** | 修改了 `evidence/task060/c-obs/watch.ps1` 与 `analyze-final.json` 的**路径引用**（属证据文件） | 任务书 §1.1 明写「**修正被搬文件内的路径引用**」，这两个文件在被搬集合内。改动的字节账目与前后 sha256 已逐条留证；被改坏的内容**当场发现并修复**（§1.3） |
| **V-4** | 前插的状态声明**比「一行」长**（5 点） | 任务书 §1.2 要求写清 3 件事；为了让「不得当完整记录使用」可执行，额外写明了观察窗口的**确切起止时刻**、开发的实际结束时刻、以及判据以 `BREAKOUT-FINDINGS.md` 为准。**原正文未改** |
| **V-5** | `BREAKOUT-FINDINGS.md` 的结论是「①④不通过」而非全通过 | 这是**证据的结论**，不是判断的偏离：P1f 与原文相反、P4b 不可归因、P4d 退化对照、⑤⑥ 根本没做。按 §5.1「只有形容词的行按不通过处理」，判不通过 |

---

## 7. `blockers`

**无阻塞**。三件事全部完成。

需要决策者**知晓但不构成阻塞**的两点：
1. ⑤⑥ 与游戏侧活链**本轮不可判定**——这是 TASK-060 执行没跑到，**不是**本批能力问题；
   要拿到结论必须**新开一轮**（按修正后的协议）。
2. `BREAKOUT-FINDINGS.md` 里 §5.3 列出的 5 个空白问题，本轮数据**结构上无法回答**。

---

## 8. `next_step_recommendation`

1. **先修编排**（`BREAKOUT-FINDINGS.md` §6 第 1 条）：观察者一律走 `mcp_watch_run.ps1` +
   开发者心跳，产物必须写死 `stop_reason` 与**观察窗口起止时刻**；否则下一轮还会「观察没跑到」。
2. **再修证据可归因性**（同 §6 第 2 条）：证据文件名唯一（带 run 序号）、对照物在**被测调用前**采样、
   每条断言直接引用证据 sha256。
3. **然后补做 ⑤⑥ 与游戏侧活链**（这是 TASK-060 原定的主验收点）。
4. 把本报告 §1.3 的**路径引用规则**与 TASK-060 的**相对路径根因**（任务书头部已记）写进
   `PLAYBOOK-group-port.md` 或后续任务书模板：**产物路径一律用绝对路径或 `modules/mcp_server/docs/...`**。

---

## 9. `commits`

| sha | 说明 |
|---|---|
| `f6f2ff3376` | `docs(mcp_server): TASK-062 recover misplaced TASK-060 artefacts + section D findings` —— 537 个文件（445 个搬移 + 78 个补回收 + 4 份报告 + 收尾证据），全部在 `modules/mcp_server/docs/**` 内 |
| *（紧随其后的一个文档收尾提交）* | `docs(mcp_server): TASK-062 record the commit sha and the git-object verification` —— 把上面的锚点与下面这条复核结果写进本报告。**刻意不引用它自己的 sha**：它包含本文件，写死自己的 sha 会导致自引用循环（本批已经踩到一次，在此说明） |

**从 git 对象本身的复核（最强形式，`实测`）**：对本批提交里 `HEAD` 的全部 **127** 份
`*.response.json.sha256` 边车，用 `git show HEAD:<path>` 取出**同级响应文件的 blob** 重算 sha256，
与边车内容逐字比对 → **127/127 相符、0 不符、0 缺失**。
⇒ 「边车 ↔ 响应原文」的自校验在**提交内容**上成立（不只是在工作树上）。

---

## 附：本批产出清单

| 文件 | 说明 |
|---|---|
| `docs/reports/BREAKOUT-TEST-PLAN.md` / `-DEV-LOG.md` / `-OBSERVATIONS.md` | 回收（含路径修正 + 头部状态声明） |
| **`docs/reports/BREAKOUT-FINDINGS.md`** | **补做的 §D 汇总** |
| **`docs/reports/REPORT-062-breakout-recovery.md`** | **本文件** |
| `docs/reports/evidence/task060/recovery/MOVE-BEFORE.sha256.tsv` / `MOVE-AFTER.sha256.tsv` | 445 文件的搬前/搬后清单 |
| `docs/reports/evidence/task060/recovery/MOVE-COMPARISON.txt` | 搬移对照摘要 |
| `docs/reports/evidence/task060/recovery/PATHFIX-TRANSFORM.tsv` | 6 个改路径引用文件的前后 sha256 |
| `docs/reports/evidence/task060/recovery/ANNOTATION-TRANSFORM.tsv` | 3 个前插标注文件的前后 sha256 |
| `docs/reports/evidence/task060/recovery/TASK-062-TOUCHED-FILES.md` | 被改文件与理由（含 `PROVENANCE.json` 哈希口径） |
| `docs/reports/evidence/task060/recovery/POST-RECOVERY-MANIFEST.sha256.tsv` | 527 行全量收尾清单 |
| `docs/reports/evidence/task060/recovery/GIT-EOL-NORMALIZATION.tsv` / `.md` | git EOL 归一化声明（27 行对照） |
| `docs/reports/evidence/task060/trace-recovered/**` | 78 个补回收的追踪/日志/脚本 + 其 sha256 清单与两份复算 JSON |
| `docs/reports/evidence/task060/DEV-LOG-raw-run.log` | §B 承诺过但从未入库的 `run.log` |
