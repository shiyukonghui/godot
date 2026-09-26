# REPORT-065A — mono 锚点缺口补齐：串行重建 mono/plain 到 HEAD，并复跑 mcp052 / mcp053 / mcp054 到 exit 0

> **D86 锚点**：本批被测对象是 **二进制 + 工作树**。
> - 被测二进制锚点 = `git rev-parse HEAD` = **`7708729982929613274e3c86ae2c9db54438add2`**（`--short=9` = **`770872998`**），
>   mono 与 plain 两个 `--version` 都自报该短 sha（见 §1.3）。
> - 被测二进制所基于的提交 = **`770872998`**：本批**未改动任何源码**，
>   `git diff -- modules/mcp_server/tools modules/mcp_server/tests` 为空（§5.1），
>   所以"二进制锚点"与"最后一个改动实现/测试/契约的提交"是同一个提交。
> - **本报告正文的提交锚点 = `6b46ff363e`**（`6b46ff363ec29a1038e4316b77d95c2950c0aed6`，
>   `docs(mcp_server): TASK-065A - rebuild mono/plain at HEAD and rerun mcp052/053/054 to exit 0`；
>   核对：`git log --format=%h --grep="TASK-065A" -- modules/mcp_server/docs/reports/REPORT-065A-mono-anchor-rerun.md`）。
>   它只增加 `docs/**`（报告 + 证据），**不含任何 `tools/**`、`tests/**`、契约改动**（已用 `git diff` 对
>   `6b46ff363e^..6b46ff363e` 与 `3daa41591a^..3daa41591a` 两条提交逐条核实为空）。
>   ⚠️ 但它会让 `HEAD` 离开 `770872998`，从而**在 `engines_match_head` 的意义上**让二进制"再次变陈旧"——
>   这是本批必须显式上报的**结构性冲突**，见 §5.6。
>   本仓库既有同型先例：`fcbeb90840 mcp: backfill TASK-061 report anchor to implementation commit A`。
> - 本批**不修改 `tools/**`、`tests/**`、契约、映射、清单、生成器**（§5.1 逐条为空 diff）。
> - **D-119 纪律**：本报告全文与全部命令、产物一律写**绝对路径**（前缀 `F:\RustProjects\godot-mcp-pro\code\godot\`，scratch 除外并显式标注）。

---

## 0. 结论（先给答案）

| # | 任务书要求 | 结论 | 证据 |
|---|---|---|---|
| 1 | **串行**重建 mono，校验 `--version == HEAD`（给短 sha 对照） | **完成**：mono `4.8.dev.mono.custom_build.770872998` == HEAD 短 sha `770872998`；单进程串行，无并发 scons | §1 |
| 1b | 随后 **如需**恢复 plain（`build_local.cmd -Force`）并复验 | **必须且完成**：plain 此前也是陈旧锚点（`92a260b68`），而三个脚本的 `engines_match_head` 要求 **plain 与 mono 同时**等于 HEAD → plain 同样重建，现为 `4.8.dev.custom_build.770872998` | §1.3、§2.3 |
| 2 | 复跑 `mcp052`/`mcp053`/`mcp054` 到 **exit 0**，给修复前后对照与逐条归因 | **完成**：三个脚本 **exit 0**，53/53、73/73、53/53 全绿；修复前为两个独立原因（陈旧字面期望 + 陈旧二进制锚点），逐条归因见 §2 | §2 |
| 3 | 若仍有红 → 逐条归因 | **没有红**：本批没有任何一项断言失败，不存在需要归因的失败项 | §2.4 |
| 4 | 五道门 + 门⑥ 三段式 + `--check-completeness/--added/--generator-version`，应 exit 0，**176 = 171 + 5** | **全部 exit 0**：门①=5 步、门③=342/23924、门④=1768/448171、门⑤=22/22 两次 PASS 清单逐行相同、门⑥ 三段式=scanned 75 / pinned 75 / 探针 101/101；三个契约机器检查全 PASS，`171 + 5 = 66 + 105 + 5` 显式成立 | §3 |
| 5 | 纪律：绝不占用/杀/重启 9877、端口 9888/9889、禁止 push、不抑制 scons、不并发 scons | **全部满足**（逐条见 §5） | §5 |

**一句话**：TASK-064 §6 如实声明的"本轮实测覆盖缺口"（三个证据脚本的端到端重跑受陈旧 mono 锚点阻碍）在本批被**关闭**——
两条腿（陈旧字面期望、陈旧二进制锚点）都已修好并各自留下可复算证据。

---

## 1. 串行重建 mono / plain 到 HEAD

### 1.1 构建命令与串行时间线（真实时间戳，无重叠）

| 步骤 | 命令（逐字） | 开始 | 结束 | scons 自报耗时 | 退出码 |
|---|---|---|---|---|---|
| mono | `modules\mcp_server\scripts\mcp057_build_mono.cmd`（内部 = `D:\Anaconda\Scripts\scons.exe platform=windows target=editor module_mono_enabled=yes tests=yes -j8`） | 2026/09/25 10:03:08.41 | 2026/09/25 10:05:06.66 | `00:01:42.06` | **0** |
| plain | `modules\mcp_server\scripts\build_local.cmd -Force`（内部 = `… platform=windows target=editor module_mono_enabled=no tests=yes -j8`） | ≈10:05:27（= 10:07:05 − 1:38） | 2026/09/25 10:07:05.17 | `00:01:38.76` | **0** |

- 两个构建**严格串行**：mono 结束（10:05:06）之后 plain 才开始；本批**任何时刻只有一个 scons 进程**（无 D62 风险）。
- 两次都删除了陈旧对象（mono：`test_mcp_server`/`test_main`/`mcp_trace.{,mono.}`；plain -Force：`test_mcp_server`/`test_main`/`mcp_trace`），
  因为 `tests/*.h` → 测试对象与 `core/version_generated.gen.h` → `mcp_trace` 这两条依赖边 scons 不维护（PLAYBOOK R-1 / TASK-054 §5.1）。
- **scons 输出未被抑制**：完整 stdout/stderr 落在日志里（下列路径），脚本另外回显退出码与日志路径；本报告 §1.4 引用了真实日志行。
  日志的原始字节为 cmd 重定向写入（控制台代码页 936），用 UTF-8 阅读其中文行会显示为乱码——这是**日志编码的环境事实**，
  不影响任何 ASCII 行（锚点、EXIT_CODE、Linking 行）的可读性。
- 日志（**绝对路径**；注意**仓库副本**用 `.log.txt` 后缀，见 §5.5 的 `.gitignore` 说明）：
  - `F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task065\builds\mono_build.log.txt`（源：`%TEMP%\mcp057\mono_build.log`）
  - `F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task065\builds\plain_build_local.log.txt`（源：`%TEMP%\mcp_server_build_local.log`）

### 1.2 HEAD 的短 sha 对照

```
git rev-parse HEAD          = 7708729982929613274e3c86ae2c9db54438add2
git rev-parse --short=9 HEAD= 770872998          <- 三个证据脚本用的就是这一条（mcp052:272 / mcp053:314 / mcp054:280）
```

### 1.3 二进制指纹：修复前 → 修复后（同一条 `--version` 判据）

| | 文件 | 修复前 | 修复后 |
|---|---|---|---|
| mono | `bin\godot.windows.editor.x86_64.mono.console.exe` | `4.8.dev.mono.custom_build.`**`cd7224274`**（2026/09/25 04:43:51）<br>sha256 `209ECCA0A2876CC8F55D6F5A694E02E4A117237172B901AC30D37BB76D1D18D9` | `4.8.dev.mono.custom_build.`**`770872998`**（2026/09/25 10:05:05）<br>sha256 `69E363A659E894A59A74DFC07C81AF77C961E95CF39EE9BDEE072DF1E6ABE61F` |
| plain | `bin\godot.windows.editor.x86_64.console.exe` | `4.8.dev.custom_build.`**`92a260b68`**（2026/09/25 09:26:17）<br>sha256 `698BCD1C130C307BC7A45C2D4880CDB6244AAD0A0F9EB382989CF38ECD94C74C` | `4.8.dev.custom_build.`**`770872998`**（2026/09/25 10:07:03）<br>sha256 `4E774901A5D53FD463D1032A34CF7C4D5D5D8C81863B9762EA73402E5F9DA10B` |
| mono（非 console） | `bin\godot.windows.editor.x86_64.mono.exe` | 196,352,512 B | 196,490,240 B（10:05:04） |
| plain（非 console） | `bin\godot.windows.editor.x86_64.exe` | 195,912,192 B | 195,912,192 B（10:07:02） |

**修复前的两个锚点各自是什么**（可核对，不是形容词）：
- `cd7224274a` = `mcp_server: TASK-059 D-8 stop pinning the generator version in checks`（mono 二进制最后构建于该提交，TASK-064 §6 已实测记载为"2026/9/25 04:43"）。
- `92a260b682` = `mcp: fix the round-2 product defects (endpoint, node paths, batch updates, parse line) TASK-063`（plain 二进制最后构建于该提交）。
- 二者都不是 HEAD `7708729982929613274e3c86ae2c9db54438add2` → 三个脚本顶部的 `engines_match_head` **必为假**。

### 1.4 构建日志的真实锚点行（逐字，来自上面两个日志文件）

mono（`mono_build.log` 最后一次运行的头部与尾部）：

```
===== mcp057_build_mono START ... 10:03:08.41 =====
SCONS: D:\Anaconda\Scripts\scons.exe (from first `scons` on PATH)
COMMAND: D:\Anaconda\Scripts\scons.exe platform=windows target=editor module_mono_enabled=yes tests=yes -j8
...
Linking Program bin\godot.windows.editor.x86_64.mono.exe ...
Linking Program bin\godot.windows.editor.x86_64.mono.console.exe ...
scons: done building targets.
INFO: Time elapsed: 00:01:42.06
EXIT_CODE=0
===== mcp057_build_mono END ... 10:05:06.66 =====
```

plain（`plain_build_local.log` 尾部）：

```
Linking Program bin\godot.windows.editor.x86_64.exe ...
Linking Program bin\godot.windows.editor.x86_64.console.exe ...
scons: done building targets.
INFO: Time elapsed: 00:01:38.76
EXIT_CODE=0
===== build_local END ... 10:07:05.17 =====
```

---

## 2. 复跑 `mcp052` / `mcp053` / `mcp054`：修复前后对照与逐条归因

### 2.1 汇总

| 脚本 | 复跑命令（逐字） | **修复前** | **修复后** | 校验条数 |
|---|---|---|---|---|
| `mcp052_added_tools_evidence.ps1` | `powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp052_added_tools_evidence.ps1` | **非零**：`engines_match_head` 假 + 2 处陈旧字面期望假 | **exit 0** | **53/53** |
| `mcp053_added_tools_evidence.ps1` | 同上（`… mcp053_added_tools_evidence.ps1`） | **非零**：`engines_match_head` 假 + 3 处陈旧字面期望假 + 1 处陈旧生成器版本假 | **exit 0** | **73/73** |
| `mcp054_forensics_and_csharp_evidence.ps1` | 同上（`… mcp054_forensics_and_csharp_evidence.ps1`，默认 `label=green`） | **非零**：>0（同一根的 2 处陈旧字面期望；该脚本不发 `engines_match_head`，只发 `mono_engine_is_the_mono_build`） | **exit 0** | **53/53** |

三个脚本的证据日志 sha256（脚本自己在结尾打印，本报告独立复算一致）：

| 脚本 | 证据日志（绝对路径） | sha256 |
|---|---|---|
| mcp052 | `F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task065\mcp052-temp-evidence\evidence.log.txt` | `931d5db2f76f4bffbb166771970e539158dc6d7cdf233ee9d6b07665a66a9222` |
| mcp053 | `F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task053\evidence.log.txt` | `c6f7bb5a8872f4dea9ff7c66c3310ff2213ff29a37014360e68285724ac4b7bc` |
| mcp054 | `F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task054\green\evidence.log.txt` | `882cf084a606db21d84bdab48f75d098731784fc6ae61bf6f0f6c3910cefbdb8` |

> `mcp052` 的 `%TEMP%\mcp052\evidence\**`（69 文件）已**整目录复制**进仓库以取得绝对路径：
> `F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task065\mcp052-temp-evidence\`。
> `mcp053`/`mcp054` 的证据本来就写在**受版本控制**的 `docs/reports/evidence/task05{3,4}/**`（它们自己的声明契约），
> 本批的复跑**就地更新**了那 40 个文件（§2.4 给出逐条前后差异），并额外把 `%TEMP%` 侧的过程产物
> （`mcp053-temp-logs\`、`mcp054-green-temp\`）复制进 `evidence\task065\`。

### 2.2 "红"不是一个原因，是**两个独立原因**（逐条归因）

`mcp052/053/054` 之前的红由**两个互不相同的缺陷**叠加而成，本批与 TASK-064 各修一个：

| 原因 | 是什么 | 谁修了 | 本批留下的证据 |
|---|---|---|---|
| **A. 陈旧字面期望** | 三个脚本把「编辑器视图 152 / 契约 175 / `added_count` 4」**钉成字面量**；TASK-063 把契约推到 **176 = 171 + 5**（编辑器视图 **153**）后，这些字面量在今天的契约上恒为**假** | **TASK-064**（脚本改动提交 `ea05a19d4b`） | `mcp064_stale_expectation_reverse_probe.ps1` **本批重跑**：13 条探针 / 0 失败 / **exit 0**，每条旧表达式 `False`、每条派生表达式 `True`（见 §2.3 的真实输出） |
| **B. 陈旧二进制锚点** | mono 停在 `cd7224274a`、plain 停在 `92a260b68`，而三个脚本要求二者的 `--version` **同时**含 HEAD 短 sha | **本批（TASK-065A）** | §1.3 的指纹表 + §2.3 的锚点谓词探针（PRE `False` → POST `True`） |

**为什么原因 A 修好之后仍然红**：`engines_match_head` 是**独立**于 A 的一条前置断言（`mcp052:275` / `mcp053:314` / `mcp054:280`），
它比较的是**二进制自报的 sha** 与 `git rev-parse --short=9 HEAD`，与契约条数无关。
TASK-064 §6 因此把它如实声明为"本轮实测覆盖缺口"，并明确建议"在有 HEAD 锚点 mono 二进制后复跑"——本批就是那次复跑。

**逐条归因（每个脚本、每条前置检查）**：

- `mcp052`：① `engines_match_head`（plain & mono 都是旧锚点）→ 假；② `endpoint_expectations_derived` 的旧式 `152/72` → 假；
  ③ `contract_meta_added_tools` 的旧式"恰好四条" → 假。修后三条全真，脚本跑到 **53/53**。
- `mcp053`：① `engines_match_head` → 假；② `contract_is_175_entries` 的旧式 `175` → 假；
  ③ `contract_meta_added_tools_is_the_four_some` 的旧式 `Count -eq 4` → 假；④ `contract_generator_version_is_1_15_0` 的旧式版本 → 假
  （生成器已是 `1.19.0`）；⑤ `endpoint_expectations_derived` 的旧式 `152/72` → 假。修后全真，脚本跑到 **73/73**。
- `mcp054`：① `contract_is_175_entries` 的旧式 `175` → 假；② `contract_meta_added_tools_is_the_four_some` 的旧式 `added_count -eq 4` → 假；
  ③ `contract_generator_version_is_1_16_0` 的旧式版本 → 假。**该脚本没有 `engines_match_head`**（它的 mono 断言只有 `mono_engine_is_the_mono_build`，
  即"版本里含 `.mono.`"），所以它的红**完全由原因 A 造成**——但它的**证据文件**里的 `mono ... versions=` 仍钉着旧锚点 `bd88b1b41`，
  本批复跑把它换成了 `770872998`（§2.4）。

### 2.3 两个"修复前 / 修复后"探针（本批真实运行，exit 0）

**(i) 陈旧字面期望**：`F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\scripts\mcp064_stale_expectation_reverse_probe.ps1`
（TASK-064 交付，本批重跑；完整输出存 `…\evidence\task065\gate5\mcp064_reverse_probe_rerun.log.txt`）

```
contract       : 176 entries, _meta.count=176, added_count=5
derived views  : editor=153 game=72 (171 ported + 5 added)
[PASS] mcp052_old_endpoint_expectations        value : False (expected False)   <- 旧式 152/72 在今天的契约上恒假
[PASS] mcp053_old_contract_is_175              value : False (expected False)   <- 旧式 175 恒假
[PASS] mcp053_old_added_tools_is_the_four_some  value : False (expected False)
[PASS] mcp053_old_endpoint_expectations        value : False (expected False)
[PASS] mcp054_old_contract_is_175              value : False (expected False)
[PASS] mcp054_old_added_count_is_4             value : False (expected False)
[PASS] mcp052_new_endpoint_expectations        value : True  (expected True)
[PASS] mcp053_new_contract_is_ported_plus_added value : True
[PASS] mcp053_new_added_tools_is_the_manifest  value : True
[PASS] mcp054_new_contract_is_ported_plus_added value : True
[PASS] mcp054_new_added_tools_is_the_manifest  value : True
[PASS] shared_contract_formula_holds           value : True
probes=13 failures=0
TASK-064 REVERSE PROBE PASS
```

**(ii) 陈旧二进制锚点**：用**三个脚本自己的谓词**（`mcp052:275`，逐字）
`($plainVersion.Contains($headSha)) -and ($monoVersion.Contains($headSha))`，在同一进程里对
「修复前记录的版本串」与「修复后的版本串」各求值一次。
产物：`F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task065\anchor_predicate_probe.log.txt`

```
# git rev-parse --short=9 HEAD = 770872998

PRE  plain=4.8.dev.custom_build.92a260b68      mono=4.8.dev.mono.custom_build.cd7224274  engines_match_head=False
POST plain=4.8.dev.custom_build.770872998     mono=4.8.dev.mono.custom_build.770872998  engines_match_head=True
```

`Check` 记录失败后**不会中止**脚本（它是在结尾按累计失败数决定退出码的，`mcp052:711`），
所以修复前该脚本会**跑完全程并以非零退出**；修复后同一脚本以 **exit 0**（53/53）结束。

### 2.4 受版本控制证据文件的**逐条前后差异**（修复前 = 提交在树上的历史证据，修复后 = 本批复跑）

`git status --short` 里被标记为已修改的受版本控制文件 = **40 个**（`task053` **23** + `task054/green` **17**）；
其中 `git diff --stat` 报**有内容差异的是 33 个（+277 −266）**，另外 7 个（`task054/green/x01/x06..x11`）
只在**行尾**上被 git 重新规范化（`git diff` 打印了 `CRLF will be replaced by LF` 警告，内容行未变）。
逐条 diff（用脚本对 `git show HEAD:` 的旧 JSON 与工作树新 JSON 做**结构化**比较，不是肉眼比对）：

| 检查 id | 修复前 | 修复后 |
|---|---|---|
| `engines_match_head`（task053） | `plain='…c4823798a' mono='…c4823798a' git HEAD='c4823798a'` | `plain='…770872998' mono='…770872998' git HEAD='770872998'` |
| `mono_engine_is_the_mono_build`（task054） | `mono='4.8.dev.mono.custom_build.bd88b1b41'` | `mono='4.8.dev.mono.custom_build.770872998'` |
| `endpoint_expectations_derived`（task053） | `editor expects 152 … from the 175 entry contract` | `editor expects 153 … from the 176 entry contract = 171 ported + 5 added` |
| `a02_editor_live_count_is_the_contract_view` | `live 9888 = 152 tool(s), derived editor view = 152 (contract 175)` | `live 9888 = 153 tool(s), derived editor view = 153 (contract 176)` |
| `b02_game_live_count_is_the_contract_view` | `live 9889 = 72 … (contract 175)` | `live 9889 = 72 … (contract 176)` |
| `c01_mono_editor_serves_the_same_contract_view` | `live mono 9888 = 152 … view = 152` | `live mono 9888 = 153 … view = 153` |
| `t_green_markers_carry_pid_role_port_and_version`（task054） | `versions=…bd88b1b41,bd88b1b41,bd88b1b41` | `versions=…770872998,770872998,770872998` |
| `status.json`（task054/green） | `{"tools":152, …}` | `{"tools":153, …}` |

**最强的单点证据**（一个受版本控制的文件，两行之差）：
`modules/mcp_server/docs/reports/evidence/task054/green/status.json`

```
-{"connections":1,"frame_count":17,"is_editor":true,"listening":true,"pending":0,"pending_connections":0,"port":9888,"server":"godot-mcp-rs","status":"ok","tools":152,...}
+{"connections":1,"frame_count":16,"is_editor":true,"listening":true,"pending":0,"pending_connections":0,"port":9888,"server":"godot-mcp-rs","status":"ok","tools":153,...}
```

被**改名**的检查（TASK-064 的派生改造，语义更强，不是放宽）：
`contract_is_175_entries` → `contract_is_ported_plus_added_entries`、
`contract_meta_added_tools_is_the_four_some` → `contract_meta_added_tools_is_the_manifest`、
`contract_generator_version_is_1_15_0/1_16_0` → `contract_generator_version_matches_the_generator`。
检查条数**只增不减**：task053 72 → **73**，task054 53 → **53**（改名不减少断言数）。

### 2.5 复跑中的两个非阻断事实（如实记录，不是缺陷、也不是本批引入）

1. **`--import` 首次尝试 `0xC0000005`、第二次成功**：三个脚本各自的导入阶段都出现
   `attempt 1/3 exit=-1073741819` → `attempt 2/3 exit=0`，日志尾部为
   `ERROR: Parameter "singleton" is null. at: EditorNode::is_cmdline_mode (editor\editor_node.cpp:6732)`。
   这与 PLAYBOOK §5 的记载一致（TASK-028 用 84 次首导**未能复现**、也无法归因到本模块），
   纪律依赖的是"校验退出码 + 有界重试 + 可诊断输出"，三者都在 `mcp_import_guard.ps1` 里生效：
   三个脚本的 `scratch_project*_imported` 最终都是 **PASS**（`attempts=2`）。诊断日志已随证据复制
   （`…\evidence\task065\mcp053-temp-logs\import-base.attempt1.log.txt` 等）。
2. **`mcp053` 的 M-5 基线是**受版本控制的**历史捕获**：`m5_baseline_is_the_pre_change_capture` 里
   `engine='4.8.dev.custom_build.c4823798a'` 是**该基线文件自身**记录的历史锚点（它的成立条件就是那一对修订），
   今天复跑的响应与之**逐字节相等**（`b07_default_response_is_byte_identical_to_the_pre_change_capture`，
   `sha256=eef36e62…` vs 基线 `eef36e62…`，295 B）。这不是陈旧锚点，**不要**把它当成本批未修干净。

---

## 3. 门（逐条给真实输出与退出码）

### 3.1 门映射（任务书的"五道门 + 门⑥ 三段式 + 三个契约检查"落到哪个进程）

| 门 | 本批如何跑 | 说明 |
|---|---|---|
| ① 契约子集逐字 | `mcp057_gates.ps1` 的 `gate1_contract_default` + 4 个 `-Group` 步骤 | 实况 `tools/list`（153 / 72）必须等于 `implemented=true` 组的并集 |
| ② 三类证据 + 跨工具活链 | **就是 §2 的 `mcp052/053/054` 复跑**（三个脚本各自包含成功/缺参/底层失败三类的真实请求-响应与跨工具活证据链） | `mcp013` 式的"活链"在 `mcp052` 的 `c1→c2→c3→c4→c5`（写工程文件→写 csproj→写 .cs→`project_build_csharp`→读回）与 `c13`（另一工具读回写入者写的内容）里 |
| ③ 模块 doctest | `bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="[MCPServer]*"` | **exit 0** |
| ④ 全引擎回归 | `bin\godot.windows.editor.x86_64.console.exe --headless --test` | **exit 0** |
| ⑤ 验收 `accept_m1.ps1` 连跑两次 | 直接连跑两次并**逐行比较 PASS 清单** | **exit 0 / exit 0**，22/22 两次，清单 `Compare-Object` = 空 |
| ⑥ 收窄点清单（三段式） | `check_narrowing_points.py` + `--coverage` + `mcp031_gate6_coverage_probes.ps1` | 三步 **exit 0** |
| extra | `check_tool_groups.py --check-completeness` / `--added` / `--generator-version` | **exit 0 / exit 0 / exit 0** |

> `mcp057_gates.ps1` 的文件头自己写明它**不含门⑤**（门⑤ 与 15 步回归在 `mcp056_regression_battery.ps1` 里），
> 所以门⑤ 由本报告**单独连跑两次**（§3.4）。本批没有跑 `mcp056` 的 15 步回归电池：那会重复本批已单独跑过的
> `accept_m1 ×2`、`mcp052/053` 等步骤，**不增加不同的检查**（该电池文件头亦如此说明）。

**运行器与日志（绝对路径）**：
- 命令：`powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp057_gates.ps1`
- 退出码：**0**（`ALL GATE STEPS EXIT 0`）
- 日志根：`C:\Users\wyl\AppData\Local\Temp\mcp057\gates\20260925-100951\`（**已整目录复制**到
  `F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task065\gates-20260925-100951\`）

### 3.2 门③ / 门④（真实输出，逐字）

```
=== gate3_doctest_mcpserver ===
    exit=0 :: [doctest] test cases:   342 |   342 passed | 0 failed | 1429 skipped | [doctest] assertions: 23924 | 23924 passed | 0 failed | | [doctest] Status: SUCCESS!
=== gate4_full_regression ===
    exit=0 :: [doctest] test cases:   1768 |   1768 passed | 0 failed | 3 skipped | [doctest] assertions: 448171 | 448171 passed | 0 failed | | [doctest] Status: SUCCESS!
```

**与上一份 HEAD 锚点报告逐字一致**（`docs/reports/REPORT-063-round2-product-defects.md:283-284`：
`342 / 23924` 与 `1768 / 448171`）——**0 failed**，passed 未减少。
本批是**在一个真正等于 HEAD 的二进制上**复现了这两个数（R-1 的"陈旧二进制假红/假绿"风险因此被排除）。

### 3.3 门⑥ 三段式（真实输出与退出码）

**(a)** `python modules\mcp_server\scripts\check_narrowing_points.py` → **exit 0**
```
  scanned     : 75 narrowing point(s) in 16 file(s)
  pinned      : 75
  coverage    : 17 declared spelling(s) (see `--coverage`); the guarantee is bounded by that set
  ...
note: 18 pinned line number(s) drifted (the pin is by marker id + occurrence, so this is not a failure; update the list when convenient)
PASS: every narrowing point of the module that one of the declared spellings matches is annotated and pinned; ...
```
`scanned == pinned == 75`（PLAYBOOK §3 门⑥ 的通过标准），**0 个未标注的收窄点**、**0 个失配的陈旧条目**；
18 条"行号漂移"按设计（pin 认 marker id + occurrence）**不是失败**。

**(b)** `python … check_narrowing_points.py --coverage` → **exit 0**
```
  scan target : modules/mcp_server/tools/**/*.{cpp,h}, code only (comments, block comments and string/char literals blanked)
  declared narrowing spellings (17): cast_real_t / cast_float / cast_static_real_t / cast_static_float /
    cast_func_real_t / cast_func_float / ctor_color / ctor_color_arg_literal / ctor_vector2 / ctor_vector2_arg_literal /
    ctor_vector3 / ctor_vector3_arg_literal / ctor_vector4 / ctor_vector4_arg_literal / lit_float_range /
    lit_real_t_alias / dbl_cast_into_float
  declared NOT covered (the boundary this gate must not be paraphrased beyond): ...
  probe regression : scripts/mcp031_gate6_coverage_probes.ps1 (one insert -> exit 1 probe per spelling)
```
`--coverage` 自己把它**不覆盖**的四类（运行时 double 隐式收窄、表达式导致的越界、整型收窄、跨文件 `typedef` 别名）逐条声明，
本报告不把它转述成"每个收窄点都必须标注"（PLAYBOOK §3 的约束）。

**(c)** `powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp031_gate6_coverage_probes.ps1` → **exit 0**
```
PASS  B1b_restored_byte_identical
PASS  B1b_worktree_clean_of_probes
101/101 checks passed; log sha256=f98554f04873c59adb62ebb1a4a937b9533419443a0ddb3ca85c2b2b2bfdd976
```
每个已声明拼写一个"插入即 exit 1"探针，且**探针后字节还原**（`B1b_restored_byte_identical`）——探针本身没有污染工作树。
日志已复制到 `…\evidence\task065\gate6-probes\probe-logs\`（**改名原因见 §5.5**：`.gitignore:266` 忽略任何名为 `logs/` 的目录）。

### 3.4 门⑤：`accept_m1.ps1` 连跑两次，PASS 清单逐行相同

| 运行 | 命令 | 退出码 | 结果 |
|---|---|---|---|
| run1 | `powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\accept_m1.ps1` | **0** | `22/22 cases passed` |
| run2 | 同上（同参数、同端口） | **0** | `22/22 cases passed` |

`Compare-Object` 两次的 `^\[(PASS|FAIL)\]` 行清单 → **`PASS LISTS IDENTICAL`**（各 22 行，run1/run2 总行数都 97）。
两次都打印：
```
implemented tools = 153 (editor endpoint) / 72 (game endpoint); contract = 176; known_deviation = per-batch verbatim gate only
```
日志（绝对路径）：`…\docs\reports\evidence\task065\gate5\accept_m1_run1.log.txt`、`…\accept_m1_run2.log.txt`。

### 3.5 门① + 三个契约机器检查（真实输出，全部 exit 0）

```
gate1_contract_default                    exit=0  group=project_read_template tools=6 contract=176 | implemented_union=153 tools (editor endpoint) / 72 tools (game endpoint) | 3/3 checks passed
gate1_contract_read_template              exit=0  group=project_read_template tools=6 contract=176 | … 3/3 checks passed
gate1_contract_validate_scripts           exit=0  group=project_validate_scripts tools=1 contract=176 | … 3/3 checks passed
gate1_contract_csharp_build               exit=0  group=project_csharp_build tools=1 contract=176 | … 3/3 checks passed
gate1_contract_editor_set_node_script_batch exit=0 group=editor_set_node_script_batch tools=1 contract=176 | … 3/3 checks passed
contract_completeness                     exit=0  TOOL-GROUPS-COMPLETENESS CHECK PASS
contract_added                            exit=0  TOOL-GROUPS-ADDED CHECK PASS
contract_generator_version                exit=0  GENERATOR-VERSION CHECK PASS (1.19.0)
```

**`176 = 171 + 5` 的机器断言（逐字，取自 `contract_completeness.log.txt`）**：

```
SOURCE  contract entries                       = 176
SOURCE  implemented by the B1/B2 manifests     = 66
SOURCE  added tools (_meta.added_tools)        = 5 (project_build_csharp, project_write_text_file,
                                                     project_validate_scripts, editor_set_node_script_batch,
                                                     editor_set_node_property_updates)
DERIVE  contract - implemented                 = 176 - 71 = 105
ASSERT  they are therefore NOT subtracted a second time (the literal 103 of TASK-015 section 1 double counts them; the derived size is 105)
ASSERT  B3 + B4 + B5 = 40 + 7 + 58 = 105 tool(s), each exactly once: PASS
ASSERT  B3/B4/B5 disjoint from B1/B2 (66 tools) and the added manifest (5 tools): PASS
ASSERT  in_contract_and_not_implemented, both directions of the difference: PASS (missing=0, foreign=0)
ASSERT  171 + 5 = 66 + 105 + 5: PASS (contract = B1/B2 union + B3/B4/B5 union + added)
ASSERT  every one of the 176 contract names is in exactly one of the four buckets: PASS
```

`contract_added.log.txt` 另外给出**双向**清单一致（`missing=0, foreign=0`，`duplicates=0`）与
`GENERATOR_VERSION == _meta.generator_version == source.generator_version: PASS (1.19.0)`；三份清单的 sha256（可复核）：
`ADDED 67cd57d0214f0485d92e7894dd112991d05d2e6d6842031cd99f238153a3f994`、
`B3 d3422a6e…`、`B4 d95d7d9e…`、`B5 85bb783e…`。

### 3.6 门③/④/⑥ 之外的 R-B2 与设置发布证据（同一批次内一并跑）

| 步骤 | 退出码 | 尾部 |
|---|---|---|
| `mcp057_rb2_failure_demo.ps1` | 0 | `R-B2 FAILURE DEMO: PASS (three drifts detected, three byte-exact restores, baseline green)`；`SAME d4e53b43840b6537af9dfbefdc77e7fb4ed6202ee23f3016503a7a53953e7ecd tools_list.renamed.json` |
| `mcp057_settings_publish_evidence.ps1` | 0 | `--- checks: 23, failures: 0 ---` / `SETTINGS-PUBLISH EVIDENCE PASS`（证据根 `%TEMP%\mcp057\settings-publish\20260925-101333`，已复制进 `…\evidence\task065\settings-publish-20260925-101333\`） |

> 说明：`rb2_failure_demo` 的尾部**逐字打印了当时整棵工作树的 `git status --porcelain`**，其中只有 §2.4 的
> `task053`/`task054` 证据文件被本批复跑更新 —— 这是本批唯一的工作树改动，且它**不触及任何被 `tools_list.renamed.json` 覆盖的实现**。

---

## 4. 时序（一次性串行，无并发）

```
10:03:08  mono scons 开始            (mcp057_build_mono.cmd)
10:05:06  mono scons 结束 exit=0     -> mono --version = 4.8.dev.mono.custom_build.770872998
10:05:27  plain scons 开始           (build_local.cmd -Force)
10:07:05  plain scons 结束 exit=0    -> plain --version = 4.8.dev.custom_build.770872998
10:07:10  mcp052 开始
10:07:50  mcp052 结束 exit=0         53/53
10:07:55  mcp053 开始
10:08:32  mcp053 结束 exit=0         73/73
10:08:40  mcp054 开始
10:09:19  mcp054 结束 exit=0         53/53
10:09:51  mcp057_gates 开始
10:13:59  mcp057_gates 结束 exit=0   ALL GATE STEPS EXIT 0
10:14:58  accept_m1 run1 结束 exit=0 22/22
10:16:56  accept_m1 run2 结束 exit=0 22/22
```

（`mcp052/053/054` 与门电池各自独占 9888/9889，**没有任何两个绑端口的进程重叠**；两个 scons 也不重叠。）

---

## 5. 纪律与收尾核实

### 5.1 未改实现代码、未改契约

```
command : git diff --stat -- modules/mcp_server/tools modules/mcp_server/tests
exit    : 0
output  : []                                     <- 空（本批一行实现/测试代码都没改）

command : git diff --stat -- modules/mcp_server/docs/tools_list.renamed.json \
                              modules/mcp_server/docs/tool-rename-map.json \
                              modules/mcp_server/docs/tool-groups-added.json \
                              modules/mcp_server/docs/tool-groups.json
exit    : 0
output  : []                                     <- 空（契约/映射/清单一字未动）

command : powershell (Get-FileHash modules\mcp_server\docs\tools_list.renamed.json -Algorithm SHA256).Hash.ToLower()
output  : d4e53b43840b6537af9dfbefdc77e7fb4ed6202ee23f3016503a7a53953e7ecd
```

契约 sha 与 `rb2_failure_demo` 内部记录的
`SAME d4e53b43840b6537af9dfbefdc77e7fb4ed6202ee23f3016503a7a53953e7ecd tools_list.renamed.json` **逐字一致**
—— 契约在本批**前后同 sha**（TASK-065 B 部分也要求"收尾核实 `git status --short` 与契约 sha 未变"，此值即 B 部分的基线）。

### 5.2 `git status --short`（本批结束时）

全部改动只有两类，逐条列出：

```
 M modules/mcp_server/docs/reports/evidence/task053/...            (23 文件，§2.4 的复跑就地更新)
 M modules/mcp_server/docs/reports/evidence/task054/green/...      (17 文件，§2.4；其中 7 个仅行尾被规范化)
?? modules/mcp_server/docs/reports/evidence/task065/               (新增证据目录，197 文件 / 2,786,276 B)
?? modules/mcp_server/docs/tasks/TASK-065-mono-anchor-and-gap-round3.md   (任务书原文，未跟踪)
?? .graphifyignore          <- 既有未跟踪物，本批未动
?? build-m0.cmd             <- 既有未跟踪物，本批未动
?? graphify-out/            <- 既有未跟踪物，本批未动
?? install-deps-m0.cmd      <- 既有未跟踪物，本批未动
```

被修改的 40 个受版本控制文件**全部**位于 `docs/reports/evidence/task05{3,4}/`，
即"这三个脚本自己的证据输出路径"，是它们声明的契约，不是本批顺手改的实现或文档。
**收尾后的既知未跟踪物仍是那四个**（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`）。

### 5.3 9877 与端口

```
运行前 : netstat -ano | findstr ":9877 :9888 :9889"  -> 无监听者（NO_LISTENER_ON_TARGET_PORTS）
运行后 : netstat -ano | findstr LISTENING | findstr ":9877 :9888 :9889" -> 无监听者
```

三个脚本各自的 `port_9877_guard` 全部 PASS，`classification=environment_fact_no_listener_before_or_after`
（**9877 在本次整个会话里从未有监听者**：本批没有启动、没有杀死、没有重启任何进程；这是**环境事实**，
不是本批的动作结果，也不是本批造成的静默）。三个脚本的 `test_ports_free_before` / `test_ports_released_after_run`
（`mcp053`）也都 PASS，它们**只杀自己启动的 PID**（`our_pids=[…]` 逐条列出）。

### 5.4 其它硬性纪律

- **未 push**：`feature/mcp-server-module` 在本仓库**没有配置上游**（`git status -sb` 首行为 `## feature/mcp-server-module`，
  无 `...origin/...`），本批未执行任何 `git push`；`origin` 仍指向 `git@github.com:shiyukonghui/godot.git`（只被读取，未被写入）。
- **不抑制 scons**：两次构建的完整输出都在日志文件中（§1.1 的路径），脚本另把退出码与日志路径回显；
  本报告 §1.4 逐字引用了日志里的 `Linking Program …` / `INFO: Time elapsed` / `EXIT_CODE=0` 行。
- **不并发 scons**：§1.1 的时间线证明两次构建不重叠；本批**总共只跑了两个 scons 进程**。
- **本批没有新建/修改任何 `.ps1`**（因此"`.ps1` 纯 ASCII"这条无对象可违反）；新增文件只有 `.md` 报告与本目录的 `.log.txt`/`.json`/`.jsonl`/`.txt` 证据。
- **唯一的新脚本产物是 `anchor_predicate_probe.log.txt`**（ASCII，由 `[IO.File]::WriteAllLines(..., ASCIIEncoding)` 写出，见 §2.3）。

### 5.5 证据文件的两处**必要改名**（`.gitignore` 的两个规则，如实声明）

本仓库的 `.gitignore` 有两条会吃掉证据的规则，本批的仓库副本因此改名（**内容逐字节未变**）：

| 规则 | 影响 | 处理 |
|---|---|---|
| `.gitignore:308` = `*.log` | `anchor_predicate_probe.log`、`builds\*.log`、`gate5\*.log`、`gates-20260925-100951\*.log`（16 个）、`mcp053-temp-logs\*.log` 全部**不会被提交** | 全部改名为 `*.log.txt`（65 个文件），与仓库既有约定一致（如受版本控制的 `evidence/task053/evidence.log.txt`） |
| `.gitignore:266` = `[Ll]ogs/` | `gate6-probes\logs\`、`mcp054-green-temp\logs\`、`settings-publish-20260925-101333\logs\` 三个**目录**整体被忽略 | 分别改名为 `probe-logs`、`process-logs`、`process-logs` |

验证：改名后
`git status --short --ignored -unormal modules/mcp_server/docs/reports/evidence/task065` 的 `!!` 行为 **0**，
`git status --short … | findstr "A "` = **197**（目录内 197 个文件**全部**被版本控制）。
**这是提交卫生问题，不是产物内容问题**；报告正文引用的路径已全部指向改名后的名称（`%TEMP%` 侧的源路径仍是原名 `.log`）。

### 5.6 结构性发现（给决策者）：`engines_match_head` 与「提交报告」之间的**固有冲突**

本批把 A 部分的结论提交为 `6b46ff363e` 之后，`git rev-parse --short=9 HEAD` 变成 `6b46ff363` / `3daa41591`，
而两个二进制的 `--version` 仍然自报 **`770872998`**（= 构建时的 HEAD）。也就是说：

> **每一次 `docs/**` 提交都会立刻让仓库里所有已构建的二进制在 `engines_match_head` 的意义上"变陈旧"。**

这不是本批引入的：plain 二进制在 TASK-063 收口时就是 `92a260b68`，而它被构建时的 HEAD 早已被 TASK-063 的
报告提交 `4e31df769d` 与 TASK-064 的两个提交推走了；这正是 TASK-064 §6 那个缺口的**结构性根因**。
它的两个直接后果，请决策者按需处置（本批**不擅自改脚本**，只记录）：

1. **这三个脚本只有在"重建完成 → 尚未提交任何东西"的窗口内才能 exit 0。** 本批的复跑（exit 0 / 53-73-53）
   发生在这个窗口内：构建于 10:03–10:07，`HEAD` 当时确实是 `770872998`。
   §2.4 里那些被就地更新的受版本控制证据记录的就是**这个窗口的真实锚点**，它们的内部一致性不受后续提交影响。
2. **"先提交报告、再重跑脚本"在现有判据下必然红**，即使工作树里的实现一行都没变。若某批需要同时有
   "报告已提交"与"三脚本 exit 0"，唯一自洽的做法是**在最后一个提交之后再串行重建一次两个引擎**
   （本批实测总代价 ≈ 3 分 21 秒：mono 1:42 + plain 1:38），让 `HEAD == 二进制自报 sha` 重新成立。
   本报告按 D86 选择的是"如实标注两个 sha"，而不是"悄悄把锚点说成 HEAD"。

**与本报告的关系**：§5.1 的空 diff 里 `HEAD` 若取 `6b46ff363e`/`3daa41591` 仍然为空（这两个提交只动 `docs/**`），
所以"最后一个改动实现/测试/契约的提交"依然是 `770872998` —— 即**二进制锚点与实现锚点是同一个提交**，
只有"HEAD 恒等于二进制"这一条在 docs 提交后不再成立。

---

## 6. 偏差与边界（如实列出）

1. **任务书写"随后如需恢复 plain"，本批判定为"必须"**：三个脚本的 `engines_match_head` 是
   `($plainVersion.Contains($headSha)) -and ($monoVersion.Contains($headSha))`（`mcp052:275`，逐字），
   **plain 与 mono 必须同时**等于 HEAD。plain 当时停在 `92a260b68`，只重建 mono 仍会红。
   因此本批重建了**两个**二进制。这是对任务书"如需"的**收窄解释**（如实声明，不悄悄扩大范围）。
2. **只重建、未改动任何实现/测试/契约**：本批是"补锚点 + 复跑"，不是修缺陷批次；
   三个脚本的红**全部**由 §2.2 的两个原因造成，**没有第三条**（§0 第 3 行）。
3. **本批未跑 `mcp056_regression_battery.ps1`（15 步回归电池）**：它内部的 15 步包含本批已单独跑过的
   `accept_m1 ×2`（门⑤）与 `mcp052/053`，另 13 步与 TASK-065A 的"补 mono 锚点缺口"无关，
   重跑只增加墙钟时间而不增加不同的检查（该电池文件头对此有同样的说明）。
   若决策者要"全量 15 步回归在 HEAD 锚点上重跑"的证据，应作为**独立批次**派发。
4. **`mcp052` 的证据原本只落在 `%TEMP%`**：任务书要求"所有产物写绝对路径（`…\docs\…`）"，
   故本批把 `%TEMP%\mcp052\evidence\**` 与两个 `%TEMP%` 侧的过程日志整目录复制进
   `…\docs\reports\evidence\task065\`。`mcp053`/`mcp054` 的证据本就在受版本控制的
   `docs/reports/evidence/task05{3,4}/**`，未被搬动，只被复跑更新。
5. **构建日志的中文行在 UTF-8 阅读下是乱码**（§1.1 末）：cmd 重定向按控制台代码页（936）写字节。
   所有本报告引用的行都是 ASCII（锚点/退出码/Linking），故不影响可核对性；如需完整中文可读日志，
   应以 GBK 解码阅读该 `.log`。
6. **决策日志**：`DECISIONS.md` 在 harness 仓库且对本模块执行者**只读**（PLAYBOOK §0），本 fork 内**不得**新建竞争性日志。
   本轮决策留痕 = 本报告 + 提交信息（提交信息将写明 "TASK-065A closes the TASK-064 section 6 coverage gap"）。
7. **副作用（结构性的，不是本批引入的选择）**：`mcp053`/`mcp054` 的复跑会**就地重写**它们自己的
   受版本控制证据（40 文件）。这正是"复跑必须留下 HEAD 锚点证据"的代价；本批把它作为交付的一部分提交，
   并在 §2.4 给出**逐条前瞻差异**，使这次重写可被独立核对，而不是"悄悄盖掉历史"。

---

## 7. 复现命令（照抄可重算本文所有数字）

```cmd
:: 0) 锚点
cd /d F:\RustProjects\godot-mcp-pro\code\godot
git rev-parse HEAD & git rev-parse --short=9 HEAD

:: 1) 串行重建（先 mono、再 plain；两次之间必须等前一个结束）
modules\mcp_server\scripts\mcp057_build_mono.cmd
bin\godot.windows.editor.x86_64.mono.console.exe --version
modules\mcp_server\scripts\build_local.cmd -Force
bin\godot.windows.editor.x86_64.console.exe --version

:: 2) 三个证据脚本复跑（各自独占 9888/9889，串行）
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp052_added_tools_evidence.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp053_added_tools_evidence.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp054_forensics_and_csharp_evidence.ps1

:: 3) 门①③④⑥ + 三个契约检查
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp057_gates.ps1

:: 4) 门⑤：连跑两次并比较 PASS 清单
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\accept_m1.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\accept_m1.ps1

:: 5) 陈旧字面期望的反例探针
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp064_stale_expectation_reverse_probe.ps1
```

---

## 8. 交付物清单（绝对路径前缀 `F:\RustProjects\godot-mcp-pro\code\godot\`）

| 路径 | 说明 |
|---|---|
| `modules\mcp_server\docs\reports\REPORT-065A-mono-anchor-rerun.md` | 本报告 |
| `modules\mcp_server\docs\reports\evidence\task065\builds\mono_build.log.txt` | mono 构建完整日志（含 `EXIT_CODE=0`；源 `%TEMP%\mcp057\mono_build.log`） |
| `modules\mcp_server\docs\reports\evidence\task065\builds\plain_build_local.log.txt` | plain 构建完整日志（源 `%TEMP%\mcp_server_build_local.log`） |
| `modules\mcp_server\docs\reports\evidence\task065\anchor_predicate_probe.log.txt` | §2.3(ii) 锚点谓词 PRE/POST 对照 |
| `modules\mcp_server\docs\reports\evidence\task065\gate5\accept_m1_run1.log.txt` / `run2.log.txt` | 门⑤ 两次真实运行 |
| `modules\mcp_server\docs\reports\evidence\task065\gate5\mcp064_reverse_probe_rerun.log.txt` | §2.3(i) 13 条陈旧期望探针（重跑，exit 0） |
| `modules\mcp_server\docs\reports\evidence\task065\gates-20260925-100951\` | 门①③④⑥ + 三个契约检查的 16 个 `*.log.txt` 与 `summary.txt` |
| `modules\mcp_server\docs\reports\evidence\task065\gate6-probes\`（含 `probe-logs\`） | 门⑥(c) 101/101 探针的日志与逐探针 JSON |
| `modules\mcp_server\docs\reports\evidence\task065\settings-publish-20260925-101333\`（含 `process-logs\`） | `mcp057_settings_publish_evidence` 的 23 检查证据 |
| `modules\mcp_server\docs\reports\evidence\task065\mcp052-temp-evidence\` | `mcp052` 的全部请求/响应/结果（原在 `%TEMP%`，为绝对路径而复制） |
| `modules\mcp_server\docs\reports\evidence\task065\mcp053-temp-logs\` | `mcp053` 的重试诊断日志（含 `0xC0000005` 首次尝试现场） |
| `modules\mcp_server\docs\reports\evidence\task065\mcp054-green-temp\`（含 `process-logs\`） | `mcp054` 的 `trace-generations.jsonl`、`synthetic-bypass.jsonl`、各进程日志 |
| `modules\mcp_server\docs\reports\evidence\task053\**`（23 文件被就地更新） | `mcp053` 自己的证据输出路径（受版本控制） |
| `modules\mcp_server\docs\reports\evidence\task054\green\**`（17 文件被就地更新） | `mcp054` 自己的证据输出路径（受版本控制） |

**返回给决策者**：见本报告 §0（≤6 行复述）。