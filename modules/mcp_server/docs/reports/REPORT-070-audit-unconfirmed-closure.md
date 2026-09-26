# REPORT-070 — 关闭 TASK-AUDIT-ENGINE 的 5 条 unconfirmed（含窗口化实测补丁 3）

- 任务书：`docs/tasks/TASK-070-audit-unconfirmed-closure.md`；手册：`docs/tasks/PLAYBOOK-group-port.md`
- 来源：`docs/reports/REPORT-AUDIT-ENGINE.md` §5 `unconfirmed` 1–5
- 契约：**176**（本批**条数不变**，`tools_list.renamed.json` / `tool-rename-map.json` / `tool-groups*.json` **一个字节未动**）
- **锚点（D86）**：本文每条实测结论都标它**测自哪个提交**。

## 0. 锚点、构建与端口（先立事实）

| 项 | 值 | 证据 |
|---|---|---|
| `git rev-parse HEAD` | `3cbaacd6bd81d12f1007ee7fbf9bb73335b5dc4c`（short9 `3cbaacd6b`） | `git rev-parse --short=9 HEAD` |
| plain `--version` | `4.8.dev.custom_build.3cbaacd6b` | `scripts\build_local.cmd -Force`（`tests=yes`，从 cmd 启动，exit 0，51 s：16:25:18→16:26:09） |
| mono `--version` | `4.8.dev.mono.custom_build.3cbaacd6b` | `scripts\mcp057_build_mono.cmd`（exit 0，**108 s**：16:38:50→16:40:38） |
| 构建是否串行 | 是。plain → mono → （本批最后）double，**任意两次 scons 无重叠**（D62） | 三段日志各有独立 START/END |
| 端口 | **9877 全程 pid=-1、无 LISTENING、从未被任何命令请求**；编辑器 9888、游戏 9889 | 每个证据脚本的 `mcp_port_guard` 行：`asked_by_us=False`、`our_ports` 只含 9888/9889 |
| 契约条数 | 176（编辑器端点 live 153 / 游戏端点 live 72 / 并集 176） | `check_contract_subset.ps1` gate1 五个调用点 + `mcp059_gates.ps1` |
| `--check-completeness` / `--added` / `--generator-version` | 三者 **exit 0**（generator 1.20.0，added sha256 `0295cf86…`，8072 B） | `%TEMP%\mcp059\gates\20260925-164214\` |

**本批新增文件**（全部落在允许范围 `modules/mcp_server/**`，未改任何 `tools/**`/`tests/**` 源码、未改 `DESIGN-DETAIL`、未改契约）：

| 文件 | 作用 |
|---|---|
| `scripts/mcp070_windowed_preserve_evidence.ps1` | ① 项②窗口化实测 |
| `scripts/mcp070_settings_save_probe.gd` | ② 的 `save()` 反向探针 |
| `scripts/mcp070_mono_csharp_evidence.ps1` | ① 项① mono/C# 四条腿 |
| `scripts/mcp070_guard_blindspot_probe.ps1` | ① 项⑤ 证据守卫盲区 + 改进原型 |
| `scripts/mcp070_build_double.cmd` | ① 项④ `precision=double` 构建命令（照 TASK-057 D-B1 的教训写下来） |
| `scripts/mcp070_double_precision_evidence.ps1` | ① 项④ 双精度实测 |

四个 `.ps1` 与两个非 `.ps1` 文件**全部纯 ASCII**（逐字节扫描 `non-ascii=0`）。

### 0.1 五条 unconfirmed 的结论一览（每条都有本轮**新证据**）

| # | 上游 unconfirmed | 本轮结论 | 新证据的核心 |
|---|---|---|---|
| ① | mono/C# **成功腿**未实测（mono 停在 `HEAD~1`） | **已关闭** | mono 串行重建到 HEAD（108 s）→ 成功腿 `exit 0` + 产物 sha256 `cf88da4f…`；能力缺失腿 `-32000` + 建议；三态 `ok`/`invalid`(+`CS1519` 等编译器原文)/`not_compiled` 全部实测（23/23 PASS） |
| ② | 补丁 3 的**窗口化**开窗保存未实测 | **已关闭**（并修正了一处上游判断的**缺失维度**） | 真开窗（日志有 `Using Device: NVIDIA … RTX 4090`）：**字节逐字节保留 + mtime 前进**（= 真的写了、且写得一字不差）；`--import`/`--headless` 连 mtime 都不动；幂等；`save()` 本体与同一组 `save()` 调用点（28 行 / 16 文件，按文件:计数逐条相同）不变（23/23 PASS） |
| ③ | 两个门驱动器**未整脚本重跑** | **已关闭** | `mcp059_gates.ps1` **exit 0**（21 步全 0）；`mcp056_regression_battery.ps1` **exit 0**（15 步 + 清单比较 + 还原裁决全 0，`accept_m1` ×2 均 23/23、`differing_lines=0`） |
| ④ | 双精度构建**未做** | **已关闭**（**本机能构建**） | `precision=double` 冷构建 **14 min 51 s / exit 0**；`FLOAT32` 专用用例在双精度二进制上 **2/2 PASS**；另发现 **F-1**：同二进制上有 7 条 `real_t` 判断式测试红（详见 §5.4） |
| ⑤ | 证据守卫的**识别盲区**只登记未构造 | **已关闭**（承认识别盲区 + 给低成本改进） | 构造了「别处删文件」：快照前已存在的未跟踪文件被删 → 守卫 manifest **0 行**；未跟踪目录内部的活动同样 0 行；电池裁决会读成 `tracked_evidence_restored`。附可运行改进原型：文件级 `-uall` 清单，**2.3 s/次**，三类差异全抓到（10/10 PASS） |

---

## 1. unconfirmed ① — mono/C# 成功腿（本轮**实测**，不再结构性推断）

脚本：`scripts/mcp070_mono_csharp_evidence.ps1`（一次运行 23 项检查，**23/23 PASS**，exit 0）。
证据根：`%TEMP%\mcp070\mono\20260925-164145\`。锚点 `3cbaacd6b`（mono 与 plain **都**是 HEAD 自报）。

上游未确认点原文（REPORT-AUDIT-ENGINE §5.1）：mono 二进制停在 `48a3c2e33`（`HEAD~1`），成功腿「不在本轮证据内」。
本轮先按 `mcp057_build_mono.cmd` 把 mono **串行重建到 HEAD**（108 s，exit 0），使两侧同锚点：

| 检查 | 结果 | 证据（真实回应） |
|---|---|---|
| `c_mono_version_is_mono_and_head` | PASS | `4.8.dev.mono.custom_build.3cbaacd6b`（同时含 `.mono.` 与 HEAD） |
| `c_plain_version_is_plain_and_head` | PASS | `4.8.dev.custom_build.3cbaacd6b`（不含 `.mono.`，含 HEAD） |
| **能力缺失腿**（**plain** 构建） | PASS | `project_build_csharp` → **`-32000`**，`message='This engine build has no C# support (no C# script language is registered in this process)'`，`data.suggestion='Run the tool from a Godot build with the C#/mono module compiled in (an official .NET build, or a local build with module_mono_enabled=yes); the plain editor cannot compile C#'` |
| 能力缺失腿未产出产物 | PASS | 产物指纹 `<no assembly>` 前后一致 |
| **成功腿**（**mono** 构建） | PASS | `exit_code=0`，`killed=False`，`timed_out=False`，stdout 含 SDK 自己的 `Mcp070Csharp -> <path>` 行；产物 **`sha256=cf88da4f52d02b8fd6a5c86c2d91f20c3c79e810d1fba2d7268da4104597f02d`**，`bytes=5632` |
| 产物确实是「真构建」出来的 | PASS | 构建前 `<no assembly>` → 构建后上述 sha256/字节数/mtime |
| **三态 `ok`** | PASS | 单数：`valid=true`，`message='Compiled: the loaded .NET assembly contains a build of this source, and the file has not been modified since that build'`；复数：`category=ok valid=true valid_count=1` |
| **三态 `not_compiled`** | PASS | 单数：`-32000`，`message='…no build of this source is loaded…'`；复数：`category=not_compiled`，`valid=null`，`reason` 点名 `CSharpScript::is_source_newer_than_assembly()`，`not_compiled_count=1` |
| **三态 `invalid` + 编译器原文** | PASS | 先让构建**真的失败**（`exit_code=1`，stdout 点名 `Broken.cs`），再问：单数 `valid=false`，`error_text` **是编译器原文**（`error CS1519` / `CS1002` / `CS1040`，本机 .NET SDK 输出为中文：`成员声明中的标记“this”无效`）；复数 `category=invalid valid=false invalid_count=1` |
| 三态**同时**出现在一个 payload 且计数自洽 | PASS | `broken=invalid edited=not_compiled plain.gd=ok`；`count=3` == `valid+invalid+not_compiled+unverifiable+language_unavailable` |
| 失败构建没有偷偷换掉产物 | PASS | 失败构建与三态询问之后，产物 sha256 仍等于成功构建后的 `cf88da4f…` |

**本轮新发现（写入报告，不是缺陷）**：

1. **`.NET SDK` 的输出是本地化的**。第一次运行我把成功判据写成 `stdout.Contains('Build succeeded')`，于是**真·成功**的构建被判 FAIL（stdout 里是 `已成功生成。` / `0 个错误`，字节原样留在 `evidence\mono_build_stdout.txt`）。
   改成**与语言无关且更强**的判据：退出码 0 + `killed=false` + `timed_out=false` + SDK 自己的 `<AssemblyName> -> <path>` 行 + 产物指纹从 `<no assembly>` 变成真实 sha256。
   **给后续批次的教训**：任何断言 `dotnet`/`godot --import` 之类外部工具 stdout 文本的测试，都必须假定输出被本地化。
2. **产物 sha256 不是可复现常量**：同一份源码两次构建得到 `83c29937…` 与 `cf88da4f…`（.NET 每次生成新的 MVID/时间戳）。所以 sha256 只能当**「那次构建发生过」的回执**，不能当「构建确定性」的证据。
3. **`project_build_csharp` 的结果字段**（实测列举，供后续引用）：`command, commands, duration_ms, effective_timeout_ms, exit_code, exit_codes, killed, non_utf8_bytes, project_files, project_root, rescanned, stderr, stderr_truncated, stdout, stdout_truncated, timed_out, timeout_ms`。

**一次新的 `0xC0000005` 观测（append-only 登记，不当作结论）**：项②的 `--import` 控制腿在**首次尝试**以 `-1073741819 (0xC0000005)` 结束，第 2 次尝试 exit 0，工程字节未被破坏；日志尾部给出 `ERROR: Parameter "singleton" is null.` + `at: EditorNode::is_cmdline_mode (editor\editor_node.cpp:6750)`。
这与 PLAYBOOK §"`--import` 崩溃是间歇性的、无法归因到本模块"的既有结论**一致**（本轮是第 5 次历史出现），本轮**不**对它下新结论；只登记：**`Import-McpProject` 的有界重试是必需的**，而它确实救回了这次运行（详见 `%TEMP%\mcp070\windowed\20260925-163616\logs\import-control.attempt1.log`）。

---

## 2. unconfirmed ② — 窗口化 `save_preserving_text()`（补丁 3）**真开窗**实测

脚本：`scripts/mcp070_windowed_preserve_evidence.ps1`（**23/23 PASS**，exit 0）。证据根：`%TEMP%\mcp070\windowed\20260925-163737\`。锚点 `3cbaacd6b`（plain）。

上游未确认点原文（§5.2）：补丁 3 的调用点带 `!cmdline_mode` 守卫，`--import`/`--headless` 都到不了它；上游只做了**源码级**核对，**没在窗口化编辑器里跑过**。

### 2.1 实测设置

- **真的开窗**：`bin\godot.windows.editor.x86_64.console.exe -e --path <proj> --mcp-port=9888`，参数表**不含 `--headless`**（原样存进 `evidence\windowed_command_line.txt`，并由 `w_windowed_launch_has_no_headless_flag` 断言）。
- **它不是「看起来像开窗」**：进程自己的日志（`logs\windowed.out.log`，逐行存进 `evidence\windowed_display_evidence.txt`）写着
  `OpenGL API 3.3.0 NVIDIA 616.56 - Compatibility - Using Device: NVIDIA - NVIDIA GeForce RTX 4090`
  与 `[MCP] listening on 127.0.0.1:9888 (editor=true, tools=153)` —— 有真实显示设备，且工具面在 9888 上确实服务。
  （`--headless` 进程从不打印渲染设备行；这就是「`DisplayServer::get_name()` 不是 `headless`、因此 `cmdline_mode=false`」的**行为证据**。）
- **夹具**：5 条手写注释（其中 **2 条在 `[input]` 内**）、`[input]` **不是末节**（后接 `[rendering]`），另加一个**引擎根本不认识的键** `mcp070_unknown_setting="a key the engine has never heard of"`；文件无 BOM（`Write-McpUtf8NoBom`）。

### 2.2 开窗前 / 开窗后（① 注释逐字、② sha256 与逐行 diff）

| 检查 | 结果 | 证据 |
|---|---|---|
| 夹具形状 | PASS | `comments=5/5 all verbatim=True; [input] at 330 < [rendering] at 528; comment line(s) inside [input]=2; sha256=b6a07dc184f9e1a9d735a16c551b9d2627a6da859792d5865fe1130364cae377` |
| **开窗真的写了文件** | PASS | sha256 **前后完全相同**（`b6a07dc1…`），但 **mtime 前进**：`639259222579937631 → 639259222967615149`（连续两次采样确认 mtime 在动） |
| **注释逐字保留** | PASS | 开窗后 `comments=5/5`，5 条**逐字**都在 |
| **`[input]` 里那条仍在 `[input]` 内** | PASS | `[input]` at 330；comment 4 at 386；comment 5 at 458；`[rendering]` at 528 —— 两条都在区间 `(330, 528)` 内 |
| 引擎不认识的键也保留 | PASS | `mcp070_unknown_setting=` 逐字仍在 |
| 没有写整文件写者的头 | PASS | 文件**不以** `; Engine configuration file.` 开头 |
| **逐行 diff + 收敛性** | PASS | **0 行差异**；且 `[application]` 之前的字节前缀、`[input]` 起的字节后缀**完全一致**（diff 全文存 `evidence\windowed_open_line_diff.txt`） |
| 就绪后到被杀之间没有别的写 | PASS | settle 后 +1.5 s 的 sha256 不变 |
| 杀进程不改文件 | PASS | 就绪时与 kill 后 sha256 相同 |

> **② 的实测结论（比上游强，且有一处反直觉）**：窗口化开路**是逐字节保留的**——因为 `save_preserving_text()` 只发布「与引擎默认值不同」的设置，而该夹具已经把要发布的都说对了，于是 `updated == text`、写回的就是文件自己的字节。
> **因此「字节相同」不能区分「写了、但写出来一样」与「根本没写」**；区分二者的是 **mtime**：只有 `!cmdline_mode` 那条分支会写，而下面对照的两条路（`--import` / `--headless`）**连 mtime 都不动**。这正是上游「只做源码级核对」缺的那一步。

### 2.3 ③ 幂等（再开一次）

| 检查 | 结果 | 证据 |
|---|---|---|
| 第二次窗口化打开 | PASS | endpoint ready=True；sha `b6a07dc1… → b6a07dc1…`；**差异行 0**；comments=5/5；**mtime 再次前进** |

即代码注释里声明的「Always write, even when `updated == text`」在窗口化路径上被测到了：**第二次也写，但字节不变**。

### 2.4 ④ 对照：`--import` 与 `--headless` 路径不变

| 检查 | 结果 | 证据 |
|---|---|---|
| `--import`（headless） | PASS | `exit=0 attempts=1`；sha 前后相同（`b6a07dc1…`）；**mtime 不变**；comments=5/5；命令：`… --headless --mcp-port=0 --path <proj> --import` |
| `--headless -e` 编辑器 | PASS | endpoint ready=True；sha 与 mtime **都不变**；comments=5/5；由本脚本 25 s 后 kill |
| 「headless 编辑器」这条对照的**声明式局限** | 已声明 | **实测**：编辑器**不认** `--quit-after`（`--quit-after 200` 的编辑器进程 180 s 后仍在运行，只能 kill；日志 `%TEMP%\mcp070-q200.log`）。所以这条对照是**有界观测 + 明确 kill**，不是退出码断言。 |

### 2.5 ⑤ 反向：其它既有 `save()` 调用点行为不变

| 检查 | 结果 | 证据 |
|---|---|---|
| `ProjectSettings.save()` **本体**不变 | PASS | 同一引擎上跑 `--headless --script res://mcp070_probe.gd -- save_whole`：exit 0；**5 条手写注释全消失**；文件**以** `; Engine configuration file.` 开头；注释行变成**引擎自己的 7 行** |
| 调用点集合不变 | PASS | `ProjectSettings::get_singleton()->save()`：现 `28 行 / 16 文件`，`2f85141a74^` 也是 `28 行 / 16 文件`；**按文件:计数** 逐条相同，added=∅ removed=∅（两份原始清单存 `evidence\save_call_sites_*.txt`） |
| 补丁 3 只动**一个**调用点 | PASS | `git show 2f85141a74 -- editor/editor_node.cpp`：`-` 掉 1 行 `save()`、`+` 回 1 行 `save()`（在 `else` 兜底分支里）、`+` 2 行 `save_preserving_text()` |

> **一处必须说明的判据修正**：我第一版把它按 **`文件:行号`** 比较，于是 **FAIL**——补丁 3 在 `editor_node.cpp` 里插入了 15 行，后面 6 个调用点的行号整体后移（`1071→1086`、`1645→1663`、`2741→2759`、`2806→2824`、`3643→3661`、`7939→7957`）。
> 「行号变了」**不是**「调用点变了」；正确的不变式是**文件与每文件计数**。报告保留这次修正的过程（三个运行目录都在，第一个 FAIL 运行是 `20260925-163135`）。

---

## 3. unconfirmed ⑤ — 证据守卫的**识别盲区**（承认 + 低成本改进）

脚本：`scripts/mcp070_guard_blindspot_probe.ps1`（**10/10 PASS**，exit 0）。证据根：`%TEMP%\mcp070\guard\20260925-163617\`。锚点 `3cbaacd6b`。

上游登记的边界（§3 / R-4）：守卫只约束 `Restore-McpEvidence` 自身，「某个步骤绕过守卫、在别处删了文件」它看不到。本轮**把这条边界变成可复现的测量**。

### 3.1 构造与结果（守卫**确实看不到**）

用一种「既看得见又看不见」的对照来钉住机制：同一个场景里，一个新出现的、位于**已跟踪目录**下的未跟踪文件**看得见**，而下面两类**看不见**。

| 场景 | 守卫 manifest | 结论 |
|---|---|---|
| **对照（看得见）**：快照后新建 `…\evidence\mcp070-blindspot-visible-plant.txt`（父目录 `evidence/` 已跟踪 → 该文件是**独立**的未跟踪条目） | `UNTOUCHED …\mcp070-blindspot-visible-plant.txt` + `SUMMARY restored=0 removed=0 kept-dirty-before=0 untouched=1` | 创建类可见 |
| **盲区 A**：快照**前**就存在的未跟踪文件 `…\mcp070-blindspot-victim-a.txt`，快照后被**别处**删掉 | **0 行提到它**；`SUMMARY` 里一个字都没有；restore 之后文件**仍然不存在** | **删除前就已存在的未跟踪文件，守卫完全看不见** |
| **盲区 B**：把 `…\evidence\task070\`（整个目录是**一个** `-unormal` 未跟踪条目）里的 `victim.txt` **改写**、并新建 `new-after-snapshot.txt` | **0 行**提到这两个文件 | **已存在未跟踪目录内部的活动，守卫完全看不见** |

机制（源码级，与实测一致）：`Get-McpEvidenceState` 只产出两个集合 `Modified`（已跟踪、内容 != HEAD）与 `Untracked`（`git status --porcelain -unormal` 的 `??` 条目，整个未跟踪目录算**一条**），`Restore-McpEvidence` 也只遍历「**新**修改」与「**新**未跟踪」——
**它从来没有一个「快照前存在、快照后消失」的循环**。所以「删除」这一半在结构上不可见。

**更严重的一层**：电池自己的裁决机制也一起失明。用电池的判据重算：`declaredLeftover.Count == 0`，即 `tracked_evidence_restored` 会打印成 **0**（`g_battery_verdict_machinery_is_blind_to_both`）——
**一次真实的静默删除会被读成「已跟踪证据已还原」**。

### 3.2 建议（低成本、可落地；已给可运行原型 + 实测代价）

**建议：把 `Untracked` 从「目录级」升级为「文件级清单」，并在 manifest 里新增三类行。**

原型（已在本探针里跑通，函数 `Get-McpUntrackedInventory` / `Compare-McpUntrackedInventory`）：
`git status --porcelain -uall` 枚举**每一个未跟踪文件**（不是目录），对每个文件记 `path -> length:LastWriteTimeUtc.Ticks`；restore 后做集合差，打印

```
MISSING-UNTRACKED  <path>     # 快照前在、现在没了
APPEARED-UNTRACKED <path>     # 现在多了
CHANGED-UNTRACKED  <path>     # 长度或 mtime 变了（可选 -HashUntracked 时用 sha256）
```

**实测它能抓到上游漏掉的那两类**：`MISSING` 抓到了盲区 A 的 victim；`APPEARED` 抓到了盲区 B 新建的文件；`CHANGED` 抓到了盲区 B 被改写的那一个。

**实测代价（本仓库当前 4029 个未跟踪文件，绝大多数是 graphify 缓存）**：

| 模式 | 第二次读取耗时 | 抓得到 |
|---|---|---|
| `-uall` + 长度 + mtime（不读文件内容） | **2 304 ms** | 删除、新建、以及**绝大多数**改写（长度或 mtime 会变） |
| 同上 + 每文件 sha256 | **6 445 ms**（种子读取 6 896 ms） | 连「等长且同秒改写」也抓得到（本轮两类都抓到了，未出现 hash 独有 ∩ 长度独有 的差别） |

**为什么这是低成本的**：它复用守卫**已有的两次快照时机**（run 前 / restore 后），只多一次 `git status -uall` + 每文件一次 `Get-Item`，不读文件内容，**不新增任何额外进程**；对一次几十分钟的电池来说是 2.3 s。

**必须与建议一起说清的三条边界（避免把它读成万能药）**：

1. 它是**探测**不是**还原**。已删除的未跟踪文件无法还原（git 里没有它）。价值在于：把「静默成功」换成**显式报警**，让 `tracked_evidence_restored` 不再对一次真实删除说 PASS。
2. 它**仍然只看得见 `git status` 看得见的东西**：`.gitignore` 覆盖的路径（`bin/`、`.godot/`）在这套机制之外——这与守卫现有语义一致（未跟踪 = `git` 不认识），不是新缺口，但要写下来。
3. 长度+mtime 会被「**等长且同秒**改写」骗过（本轮实测未出现，故**未**把它做成默认；需要内容级保证就开 `-HashUntracked`，代价 ~6.4 s，或只对 `mcp_server/**` 子树开）。

**本探针自身是否干净**：`git status --porcelain -uall` 前后都是 **4026 行、diff 0 行**（`g_repository_left_exactly_as_it_started`）——探针植入的 6 个路径全部清掉，仓库回到起点。

---

## 4. unconfirmed ③ — 两个门驱动器**整脚本重跑**

上游原文（§5.3）：「恒真断言」「证据守卫」被这两个驱动器调用，但**只**由 `git grep` 行号 + 单独跑被调命令（exit 0）证明过，**没有重跑整个驱动器**。

### 4.1 `scripts\mcp059_gates.ps1`（整脚本重跑）

- 命令：`powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp059_gates.ps1`
- **进程退出码：0**；末行 `ALL GATE STEPS EXIT 0`
- 日志根：`%TEMP%\mcp059\gates\20260925-164214\`（`summary.txt` + 每个步骤一份 `.log`）
- **步骤清单（21 步，全部 exit 0）**：

| # | 步骤 | exit | 要点 |
|---|---|---|---|
| 1 | `gate3_doctest_mcpserver` | 0 | `345 passed / 0 failed / 1429 skipped`，`23971 assertions / 0 failed` |
| 2 | `gate4_full_regression` | 0 | `1771 passed / 0 failed / 3 skipped`，`448218 assertions / 0 failed` |
| 3 | `gate6_narrowing` | 0 | 门⑥ 三段式之一（清单 + 标记 + 理由） |
| 4 | `gate6_narrowing_coverage` | 0 | 已声明拼写集合 + 集合外打印 |
| 5 | `gate6_coverage_probes` | 0 | **101/101**（每种拼写「插入即 exit 1」探针） |
| 6 | `t059_tautology_scan` | 0 | `TAUTOLOGY CHECK PASS`（命中全部已 pin） |
| 7 | `t059_tautology_probes` | 0 | `18/18`（14 声明拼写 + 4 近似反例） |
| 8 | `t059_tautology_coverage` | 0 | 有限集合声明 |
| 9 | `contract_completeness` | 0 | `TOOL-GROUPS-COMPLETENESS CHECK PASS`（ADDED 8072 B / `0295cf86…`） |
| 10 | `contract_added` | 0 | `TOOL-GROUPS-ADDED CHECK PASS`（同 sha） |
| 11 | `contract_generator_version` | 0 | `GENERATOR-VERSION CHECK PASS (1.20.0)` |
| 12 | `t059_contract_pre_post` | 0 | 只有 5 条 description override + generator 版本 + 审计记录移动 |
| 13 | `rb2_failure_demo` | 0 | 三种漂移全部检出并**逐字节还原**；基线绿 |
| 14 | `t059_d5_scons_probe_demo` | 0 | scons 解释器探测的三条来源 + 可读错误 |
| 15 | `gate1_contract_default` | 0 | `contract=176`，`implemented_union=153/72`，`3/3 checks` |
| 16 | `gate1_contract_read_template` | 0 | 同上 |
| 17 | `gate1_contract_validate_scripts` | 0 | 同上 |
| 18 | `gate1_contract_csharp_build` | 0 | 同上 |
| 19 | `gate1_contract_editor_set_node_script_batch` | 0 | 同上 |
| 20 | `t059_section_switch_evidence` | 0 | `checks: 30, failures: 0` |
| 21 | `patch2_settings_publish_evidence` | 0 | `checks: 23, failures: 0` |
| 22 | `t059_d2_failure_demo` | 0 | 3 次证据运行，`demo failures: 0` |

> 步骤 13 的 `git status --porcelain (whole tree)` 行**原样**打印了本批的未跟踪文件（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`、`TASK-070-…md`、以及 6 个 `mcp070_*` 新文件）—— 该脚本**只记录、不据此判失败**（源码事实：`mcp041/042/043/050/051/054_*gates*` 与 `rb2_failure_demo` 都是 `Add-Content`/`Say` 记录；`mcp056_regression_battery` 的裁决也已收窄到「已声明集合」）。

### 4.2 `scripts\mcp056_regression_battery.ps1`（整脚本重跑）

- 命令：`powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp056_regression_battery.ps1`
- **进程退出码：0**；末行 `ALL REGRESSION STEPS EXIT 0`
- 证据根：`%TEMP%\mcp_server_regression\20260925-164814\`（`summary.txt` + 15 份步骤 `.log` + `accept_m1_pass_list_compare.txt` + `restore_manifest.txt` + 前后 `git_status_short_*` / `git_diff_stat_*`）
- 锚点 `3cbaacd6b`：plain 与 mono **都**是 HEAD 自报（步骤 `mcp052`/`mcp053` 内的 `engines_match_head` 因此成立——上游「mono 停在 `HEAD~1`」的问题在本轮**已由重建消除**）

**步骤清单（15 步 + 1 条清单比较 + 1 条还原裁决，全部 exit 0）**：

| # | 步骤 | exit | 要点 |
|---|---|---|---|
| 1 | `accept_m1_run1` | 0 | `23/23 cases passed`；`implemented tools = 153 (editor) / 72 (game)`；`contract = 176` |
| 2 | `accept_m1_run2` | 0 | 同上（第二次） |
| 3 | `mcp041_gates` | 0 | `ALL STEPS EXIT 0 (17 step line(s))` |
| 4 | `mcp042_gates` | 0 | `ALL STEPS EXIT 0 (19 step line(s))` |
| 5 | `mcp043_gates` | 0 | `ALL STEPS EXIT 0 (29 step line(s))` |
| 6 | `mcp010_b2_observation_evidence` | 0 | `phase game: 29/29 checks passed` |
| 7 | `mcp019_b4_evidence` | 0 | `H1_user_editor_port_9877_guard` PASS |
| 8 | `mcp027_object_shape_and_paths_evidence` | 0 | `phase green: 60/60 checks passed` |
| 9 | `mcp044_capture_evidence` | 0 | `40/40 checks passed (phase editor)` |
| 10 | `mcp045_pixel_compare_cost` | 0 | `15/15 checks passed` |
| 11 | `mcp046_capture_encode_cost` | 0 | `23/23 checks passed` |
| 12 | `mcp050_parameter_guidance_evidence` | 0 | 9877 guard pass；`task050\red\summary.json` sha256 `1a294660…` |
| 13 | `mcp051_b_tier_evidence` | 0 | 9877 guard pass；`task051\red\summary.json` sha256 `203af5ad…` |
| 14 | `mcp052_added_tools_evidence` | 0 | `53/53 checks passed`（含 `engines_match_head`） |
| 15 | `mcp053_added_tools_evidence` | 0 | `73/73 checks passed`（含 `engines_match_head`） |
| — | `accept_m1_pass_lists_agree` | **0** | `accept_m1_run1 checks=23 accept_m1_run2 checks=23 differing_lines=0` |
| — | `tracked_evidence_restored` | **0** | `declared leftovers=0 (every declared artifact is back); undeclared paths left alone=1; restore failures=0; git diff --stat after=0 line(s)` |

**还原清单（`restore_manifest.txt`）**：`RESTORED` 56 条（task050/051/053 三条根下）+ `RESTORED-NEW` 1 条（`task051/red/e20_child_status.json`，唯一一步新建的文件）+ `SUMMARY restored=56 removed=1 kept-dirty-before=0 untouched=1`。
被 `UNTOUCHED` 的那 1 条**正是本报告本身**（`REPORT-070-audit-unconfirmed-closure.md`，电池开跑后才写出）——这是 TASK-069「按声明还原、声明外的路径只报告不动」的**一次现场复现**，而且它出现在 `git status --short (after)` 里、`git diff --stat after = 0 line(s)`，说明**没有任何已跟踪文件被留在改动状态**。

**关于「工作树须干净」这一疑虑的结论（任务书要求：「若仍因工作树须干净非零，必须证明那是自检而非回归」）**：

- 电池**没有**因工作树非零：进程退出码 **0**。
- 但它确实**打印**了一整棵脏树（`mcp041/042/043_gates` 的 `tree dirty after the run:` 行，以及 `rb2_failure_demo` 的 `git status --porcelain (whole tree)`）。**源码事实**：这些行都是 `Add-Content`/`Say` 的**记录**，没有任何一处把它变成判据；电池自己的裁决在 TASK-069 之后已**收窄到「已声明集合」**（`$declaredLeftover` / `$restoreFailed`），声明外的路径只 `UNTOUCHED`。
- 因此本批**不存在**这条失败；同时本轮给出了该疑虑的**判定依据**：判据看的是 `declared leftovers=0` 与 `restore failures=0`，而不是 `git status` 是否为空。本批是一次**活证明**：一个未声明的未跟踪文件（我的报告）出现在 atfter 快照里，电池**照样 PASS**。

---

## 5. unconfirmed ④ — `precision=double` 构建与 `ValueSlot::FLOAT32` 判定（**本机能构建，已实测**）

上游原文（§5.4）：「`ValueSlot::FLOAT32` 的设计主张是源码级结论，与本机单精度二进制无关，本轮未做双精度构建」。

### 5.1 构建：能构建，且**不干扰**另两个变体（**14 分 51 秒**，exit 0）

- 命令：`modules\mcp_server\scripts\mcp070_build_double.cmd` → `scons platform=windows target=editor module_mono_enabled=no tests=yes precision=double -j8`
- **START 17:18:52 → END 17:33:43 = 14 min 51 s**，`scons: done building targets.`，`EXIT_CODE=0`；日志 `%TEMP%\mcp070\double_build.log`（~3000 行，未抑制）
- 构建串行：紧接在电池（17:0x 结束）之后，**没有与任何其它 scons 重叠**
- 产物（**独立变体，不覆盖任何东西**）：
  `bin\godot.windows.editor.double.x86_64.console.exe`，`--version = 4.8.dev.double.custom_build.3cbaacd6b`，sha256 `ab4835e8c4a76a15f2bdc620eaa5bbd113694b06df046b96c1bf8f0eccdec5ce`，300544 B
- **plain 二进制事后复验未受影响**：`4.8.dev.custom_build.3cbaacd6b`（根因是 `SConstruct:1051-1053` 把 `.double` 加进 `suffix`，`:1171-1173` 再把它拼进 `PROGSUFFIX`/`PROGSUFFIX_WRAP`/`OBJSUFFIX`）。因此**不需要**任何「构建完再把 plain 编回来」的收尾步骤。

> 「是否需要构建」的结论：**需要、且值得**——14 min 51 s 的实测代价，换掉一条挂了 5 份报告（REPORT-023/035/037、REPORT-AUDIT-M4d/M4e）的「双精度未验」。

### 5.2 这个二进制**真的是**双精度（两道独立证据）

| 检查 | 结果 | 证据 |
|---|---|---|
| 名字与锚点 | PASS | `--version` 同时含 `.double.` 与 HEAD |
| `real_t` 宽度探针（同一段 GDScript，两个二进制各跑一次） | PASS | **double**：`Vector2(1e300,0).x` 打印**1e300 的完整 301 位十进制展开**且 `is_finite=true`；**single 对照**：同一段代码打印 `x=inf is_finite=false` |
| 条件编译见证（同一批用例集 `[MCPServer]*`） | PASS | single 报 **23971** 条断言，double 报 **23961** 条，**少 10 条** —— 这 10 条只能位于 `if (sizeof(real_t) == 4)` 块里，即 `real_t` 在该二进制里真的是 8 字节 |
| 没有把别的二进制改坏 | PASS | single 仍自报 plain+HEAD；double 自报 `.double.`+HEAD |

### 5.3 `ValueSlot::FLOAT32` 判定：**在双精度构建上通过**

| 检查 | 结果 | 证据 |
|---|---|---|
| **专用用例** `[MCPServer] TASK-023 D-15: the FLOAT32 slot is judged in every build, REAL_T follows the build` | **PASS** | double 二进制：`test cases: 2 | 2 passed | 0 failed | 0 skipped`，exit 0（single 对照同样 2/2） |
| 它断言的是什么 | — | `FLOAT32` **拒绝** `1e300 / 3.5e38 / -3.5e38 / 1e-300 / 1e-46`（含 `-32602` 与 `3.4e38`/`1.4e-45` 的错误文本）、**接受** `0 / 0.3 / 1.0 / -1.5 / 1e30 / -1e30 / 1e-30`；且 `coerce_to_property_type(…, PACKED_FLOAT32_ARRAY)` 拒绝 `1e300` 元素 |

**为什么这条用例在双精度构建上是一个真正的判别器（而不是「碰巧绿」）**：`tools/tool_helpers.cpp:1801-1807` 的判定是
```cpp
const bool judge_32_bit = p_slot == ValueSlot::FLOAT32 || (#ifdef REAL_T_IS_DOUBLE false; #else p_slot == ValueSlot::REAL_T; #endif)
```
它的 `FLOAT32` 那一半是**无条件编译进去的**；它的断言（`CHECK_FALSE(...FLOAT32...)`）在双精度构建下**同样执行**。若 `FLOAT32` 退化成 `REAL_T`（或把 32 位判定放进 `#ifndef REAL_T_IS_DOUBLE`），这条用例在**这个**二进制上会直接失败。它没有失败。
→ **「`FLOAT32` 在任何构建配置下都按 32 位判」从「源码级 + 单元级结论（单精度二进制上不可观测）」升级为「双精度二进制上的实测」。**

### 5.4 **本轮新发现 F-1（重要，非阻塞）**：双精度构建上模块 doctest 有 **7 条红**，且**红在测试而不是门**

| 事实 | 证据 |
|---|---|
| double：`345 cases | 338 passed | **7 failed**`；`assertions: 23961 | 23862 passed | **99 failed**` | `evidence\doctest_module_double.txt`、`doctest_double_failing_cases.txt` |
| single（同一用例集）：`345 | 345 passed | 0 failed` | `evidence\doctest_module_single.txt` + 门③ |
| 红的 7 条（逐条列出） | `TASK-022 D-4: a scalar real_t member refuses a value that does not survive the slot`；`TASK-022 D-4: the batch paths refuse a scalar real_t overflow before any write`；`TASK-022: one gate decides the width of every narrowing slot`；`TASK-025 E-3 (write half): a rect component outside its slot is refused by the existing gate`；`TASK-028 G-1: a sub-property path writes one component through the same gate`；`TASK-028 G-1: Vector4 components, nested objects and Dictionary members`；`TASK-033 the Quaternion read and write shapes are closed` |
| **没有一条失败断言与 `FLOAT32` 有关** | 失败输出里 `ERROR:` 行**点名 `FLOAT32` 的 = 0 条**；点名 `REAL_T` 的 = 20 条；7 条用例全部落在已知的 `real_t` 宽度类里（off-class = 0） |
| 它们为什么红（读源码） | 它们断言「**标量 `real_t` 成员** 或 **`Vector2/Rect2/Vector4/Quaternion` 的分量** 拒绝 `1e300`」。例：`test_mcp_server.h:14436-14439` 的注释写着「`rotation = 1e300` -> `inf`」，这是**单精度**的事实；实测双精度下 `holder->v4()` 真的变成了 `(9,2,3, 1e300)`（`CHECK( holder->v4() == Vector4(9,2,3,4) )` 失败并打印了那个 301 位数）。`Vector4`/`Quaternion` 的四个分量在 `core/math/vector4.h:51-54`、`core/math/quaternion.h:38-41` 里是 **`real_t`**，`Rect2::position/size` 同样是 `real_t` |
| 判定 | 在双精度构建上，`REAL_T` **接受** `1e300` 是**声明的设计**（`tool_helpers.cpp:1801-1807`：`REAL_T` 随构建走）；真正「单精度特有」的是**这些测试的期望**。**不是产品缺陷，是测试的构建配置独立性缺口** |
| 影响 | 今天不影响交付（发布的是单精度构建，门③ 345/345 绿）；**一旦有人给双精度构建装门③，它会红** |
| 已有的正确写法（照它改即可） | 同一个文件里的 D-15 用例已经示范：`test_mcp_server.h:15043` 用 `if (sizeof(real_t) == 4) { … }` 把 `REAL_T` 那一半做成构建条件。把这 7 条也包一下，或把它们的目标改成 `FLOAT32` 槽的成员（`Color` 分量 / `PackedFloat32Array`），红就消失了 |

**这条发现**同时解释了 §5.2 的断言数差（single 23971 vs double 23961）：差出来的 10 条正是条件编译掉的断言。

**给决策者的两个选项（本轮不做，因为它属于「改测试」而不是「关 unconfirmed」）**：
- **A（保守）**：只把 F-1 登记为「测试缺口 + 双精度构建不进 CI 门」，不改测试；
- **B（推荐）**：把 7 条里「本来想测 32 位收窄」的断言改指向 `FLOAT32` 槽（`Color` 分量 / `PackedFloat32Array` 元素），把「本来就想测 `real_t` 的」用 `if (sizeof(real_t) == 4)` 包起来（与 D-15 同一写法）。改完双精度构建上应当 `345/345`，届时可把双精度加进门③的一个**可选**变体。

---

## 6. 门与纪律收口

### 6.1 五道门（本批**没有**新增工具、没有改契约/映射/生成器/工具源码，因此门的通过标准与上一个批次完全相同）

| 门 | 命令 | 结果（锚点 `3cbaacd6b`） |
|---|---|---|
| ① 契约子集逐字 | `check_contract_subset.ps1`（默认 + `project_read_template` / `project_validate_scripts` / `project_csharp_build` / `editor_set_node_script_batch`） | 五个调用点**各 3/3 checks passed**；`contract=176`；`implemented_union=153 (editor) / 72 (game)` |
| ② 三类证据 | 见 §1/§2 的**真实请求-响应**（`curl.exe -s -o` 落盘 + 每份回应的 sha256） | 各 23 项检查全绿；**本批的 ② 是「逐条 unconfirmed 的新证据」，不是复述上游** |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **345 passed / 0 failed / 1429 skipped**，**23971 assertions / 0 failed**（§5.4 补充：**同一用例集在 `precision=double` 二进制上是 338/7**，见 F-1） |
| ④ 全引擎回归 | `--headless --test` | **1771 passed / 0 failed / 3 skipped**，**448218 assertions / 0 failed** |
| ⑤ `accept_m1.ps1` ×2 | 电池步骤 1/2 + 清单比较 | 两次都 `23/23`；`differing_lines=0`（`accept_m1_pass_list_compare.txt`） |
| ⑥ 收窄点清单（三段式） | `check_narrowing_points.py` + `--coverage` + `mcp031_gate6_coverage_probes.ps1` | **全部 exit 0**；探针 **101/101** |
| 附加：契约完整性 | `check_tool_groups.py --check-completeness` / `--added` / `--generator-version` | **三者 exit 0**（generator `1.20.0`，added `0295cf86…`，8072 B） |

门⑥ 的**三段式**在本报告里的落点（§22.3b 规则 4：「任何新增/修改收窄代码的批次必须逐条列出新增点 × 它经过的闸门 × 证据」）：
**本批新增收窄点 = 0**。本批只新增了 `modules/mcp_server/scripts/**` 下的 6 个证据脚本 + 1 份报告，**没有一行 `tools/**` 或 `tests/**` 的改动**（`git status --porcelain` 对 `modules/mcp_server/tools`、`modules/mcp_server/tests`、契约/映射/组清单**均为空**；脚本自己也在 `c_no_tracked_file_was_touched` 里断言了这一点）。因此门⑥ 在这里的角色是**回归**（证明既有 30 个收窄点的标记与理由没被这批动作扰动），而不是新点的证据。

### 6.2 纪律

- **端口**：9877 全程无监听、无进程、**任何命令都没有请求过它**（每个 guard 行都有 `asked_by_us=False`）；测试只用 9888/9889，收工时 `port 9888 owner=-1`。
- **构建串行**：plain（16:25:18–16:26:09）→ mono（16:38:50–16:40:38）→ double（见 §5），三段日志的 START/END **互不重叠**；每次构建都从 cmd 启动、都**没有**抑制 scons 输出（日志落盘 + 控制台回显），都保留真实 `EXIT_CODE`。
- **`.ps1` 纯 ASCII**：6 个新文件逐字节扫描 `non-ascii=0`（含 `.gd`）。
- **证据采集**：一律 `curl.exe -s -o <file>` 落盘 + 逐份 sha256（每份 `*.request.json` / `*.response.json` 都在证据根里，摘要打印了 `curl_exit/bytes/sha256`）；**没有**用 `Out-File`/管道承载响应体。
- **红相位输出当场保存**：项①的第一次运行（`%TEMP%\mcp070\mono\20260925-164046\`）是一次**真·红相位**（`c_mono_build_succeeds_and_the_assembly_is_real` FAIL，原因是判据被本地化输出骗了），它的完整输出与证据**原样保留**；项②的第一次运行（`%TEMP%\mcp070\windowed\20260925-163135\`）与第二次（`…-163616\`）同理（`w_windowed_open_moved_the_file` 与 `w_other_save_call_sites_are_untouched` 各 FAIL 一次）。三次修正都写在正文里，**没有**用「重跑一次绿了」把它抹掉。
- **禁止 push**：本轮**没有**任何 `git push`；也没有任何 `git commit`（见 §7）。
- **不得改 `DESIGN-DETAIL`**：未改（`git status` 对 `modules/mcp_server/docs/DESIGN-DETAIL.md` 为空）。
- **hof-rs 只读**：未触碰 `F:\moonbit-hof-rs` 下任何文件。
- **不占用/杀/重启 9877**：未发生；`mcp_port_guard` 每次都以 `environment_fact_no_listener_before_or_after` 记录（本轮用户没有开编辑器，这是**环境事实**，脚本按 TASK-041/042 的口径如实分类，没有把它当成「本期证明了没占用」）。

---

## 7. deviations / blockers / next step

### 7.1 deviations（与手册/任务书的偏离，逐条显式列出）

1. **新增了 6 个证据脚本 + 1 份报告，未改任何工具/测试源码。** 任务书允许改 `modules/mcp_server/**`；本轮全部落在 `scripts/**` 与 `docs/reports/**`，`tools/**`、`tests/**`、契约、映射、组清单、`DESIGN-DETAIL.md` **零改动**。
2. **新脚本不写入任何已跟踪文件**（与多数历史证据脚本不同）：四个 `mcp070_*` 脚本的证据根一律在 `%TEMP%\mcp070\**`。理由：①项③要求整脚本重跑两个门驱动器，而它们会写**已跟踪**的证据文件并靠 `mcp070`… 不，靠 `mcp_evidence_guard` 还原；如果本批的新脚本也写已跟踪文件，只会给那两次重跑增加噪声与串扰。代价：报告里的证据是 `%TEMP%` 路径而不是仓库内路径（报告里给了绝对路径与 sha256，可复现）。
3. **没有 git commit。** 任务书没有要求提交，且本批的产物（报告 + 证据脚本）与决策层的提交节奏由决策者掌握；仓库末尾状态只有**未跟踪**的新文件，没有一个已跟踪文件处于改动状态（`git diff --stat = 0`）。
4. **项②的「逐行 diff」最后是 0 行。** 任务书要求「② `sha256` 与逐行 `diff`」，我给的是：sha256 前后相同 + **0 行差异** + 前缀/后缀逐字节相同 + **mtime 前进**（证明写确实发生）。这是**实测结果**，不是省略：窗口化开路在这个夹具上是逐字节保留的。上游「开窗会吃掉注释」的缺陷**没有**复现，**修复有效**。
5. **项②的 headless 对照是有界观测**（编辑器不认 `--quit-after`，实测），已在该检查的 evidence 字段里声明，不是退出码断言。
6. **项⑤只做「探测」侧改进，没有改生产守卫脚本。** 改进以可运行原型 + 实测代价给出（§3.2），**没有**把它落到 `mcp_evidence_guard.ps1`：那会改动一个被 15 个步骤与多个门脚本共用的判据实现，属于「先改工具再证明」的顺序错误，也可能让本批自己的门变色。是否采纳由决策者定。
7. **`.ps1` 中出现并保留了三次「红相位 → 修正判据 → 复跑」**（见 §6.2）；三个红运行的证据目录都留着，报告里说明了每一次修正的**原因**而不是只贴绿输出。

### 7.2 报告本身的两个已知限制（诚实声明）

1. **项①的产物 sha256 只对「那次构建」有效**（同源码两次构建 sha256 不同，.NET 每次写新的 MVID/时间戳）。它证明「真构建发生过」，**不**证明构建可复现。
2. **项②没有构造出「开窗后确有字节差异」的用例**。我尝试过把「引擎会把 `application/config/features` 补进 `[application]`」当作差异来源，**实测不成立**（该键是 `hide_from_editor` 的引擎内部设置，不进入发布的 section 集合，见 `core/config/project_settings.cpp:1276-1278` 的 `hide_from_editor` 跳过 + `:2490` 的 `GLOBAL_DEF_INTERNAL`）。所以本轮**没有**一个「diff 非空且被正确约束在目标 section 内」的窗口化样本；那一路的 section 级收敛性由 `mcp059_section_switch_evidence.ps1`（30/30，同批门内）通过 **工具路径** 覆盖，而不是通过窗口化开路覆盖。**这是本轮诚实留下的一个缺口**，登记为 `next_step`。

### 7.3 blockers

- **无阻塞项。** 5 条 unconfirmed 全部拿到新证据（结论见 §0.1）。
- **一条非阻塞的新发现**：F-1（§5.4，双精度构建上 7 条 `real_t` 判断式 doctest 红）。它**不影响今天的交付**（发布构建是单精度，门③ 345/345），但**必须被记录**，因为它是「加一个构建变体就会红」的那类。

### 7.4 next_step_recommendation（给决策者）

1. **提交本批**：6 个 `mcp070_*` 证据脚本 + `REPORT-070-audit-unconfirmed-closure.md`（建议一条提交，英文信息，形如 `mcp_server: TASK-070 close the five audit unconfirmeds (windowed patch-3 measurement, mono C# success leg, guard blind spots, double-precision build)`）。
2. **处理 F-1（推荐选项 B）**：把 7 条用例按 `if (sizeof(real_t) == 4)` 包起来（同文件 D-15 用例已经示范，`test_mcp_server.h:15043`），或把「本来想测 32 位收窄」的断言改指向 `FLOAT32` 槽（`Color` 分量 / `PackedFloat32Array` 元素）。改完双精度二进制上应为 `345/345`，届时可把 `precision=double` 作为门③ 的**可选变体**（构建 ~15 min，`mcp070_build_double.cmd` 已把命令写下来）。**这项改动是「改测试」，不属于本批「关 unconfirmed」的范围，所以本轮没做。**
3. **§3.2 的守卫改进**：若采纳「未跟踪文件级清单」，建议作为**独立任务**做（改 `mcp_evidence_guard.ps1` + 两个门驱动器 + `mcp064/mcp069` 系探针的回归），并保留 `-HashUntracked` 为可选开关。
4. **补上 §7.2 的限制 #2**：构造一个「窗口化开窗后 `project.godot` 确有字节变化、且变化被约束在目标 section 内」的用例，把窗口化路径的 section 收敛性也变成实测。
5. **§1 的本地化教训**：建议在 PLAYBOOK §7 纪律补强的下一版里记一条「断言外部工具 stdout 文本前先确认输出是否被本地化」（本轮第一次运行正是被它骗出一个假 FAIL）。
6. **`0xC0000005` 的第 5 次出现**（§1 末尾）建议按既有口径 append-only 登记到 `REPORT-028` 的汇总里，不新开结论。
