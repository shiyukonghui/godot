# REPORT-048 — 收尾三件：`mcp010` 不变式改派生 + `mcp014` 一行缺陷 + 补跑未跑的门批次

> 任务书：`docs/tasks/TASK-048-derived-invariants-and-battery.md`；手册：`docs/tasks/PLAYBOOK-group-port.md`（已完整阅读）。
> 主要产出：`scripts/mcp010_b2_observation_evidence.ps1`（4 条不变式改为派生）、
> `scripts/mcp014_m3_evidence.ps1`（一行缺陷修复）、`docs/reports/MILESTONES-CLOSURE.md` §4（「未跑」→ 真实结果）。
> **不改模块实现、不改契约**：本批**没有动任何 `*.cpp` / `*.h` / 契约 / 映射 / 生成器**，
> 只动 `modules/mcp_server/scripts/**` 与 `docs/**`；证据见 §5.1。

## 0. status / commits / 环境

| 项 | 值 |
|---|---|
| status | **完成**（三件事全部交付；§2 遗留 2 条红为**任务书未授权**的陈旧不变式，只登记不修改，见 §2.4） |
| 分支 | `feature/mcp-server-module` |
| 起始 HEAD | `019c4b0198`（short 9 `019c4b019`），任务是「已实现 171/171」的收尾 |
| commits | 见 §7（脚本一条 `cef846a418`；本报告 + `MILESTONES-CLOSURE.md` 一条纯文档） |
| 非 mono 引擎 | `bin\godot.windows.editor.x86_64.console.exe`，`--version = 4.8.dev.custom_build.019c4b019` == HEAD；**恢复构建后** sha256 `690807dff17d543b4cf53fd978f89e5431bd74690a4a46cfd532ea10d2eb62ca` |
| mono 引擎 | `bin\godot.windows.editor.x86_64.mono.console.exe`，`--version = 4.8.dev.mono.custom_build.019c4b019` == HEAD，sha256 `d4ad5c95e3c558e56e5213071907b61eb65d915d29f08829511f62eaeb72f654` |
| 端口 | 开工/每次运行前后核对：9877 **全程无监听者**（用户编辑器未运行），**从未占用/杀/重启**；只用 9888/9889；收尾时 9877/9888/9889 均无 LISTENING |
| 构建 | 三次，**全部串行**、任意时刻只有一个 scons、**未抑制输出**：① `build_local.cmd -Force`（tests=yes，从 cmd 启动）② mono scons ③ `build_local.cmd -Force` 恢复非 mono |
| 未 push | 只有本地提交 |
| 日志根 | `%TEMP%\task048-logs\`、`%TEMP%\mcp041\gates\`、`%TEMP%\mcp042\gates\`、`%TEMP%\mcp043\gates\`、`%TEMP%\task048-final-gates\`、`%TEMP%\mcp044-evidence\`、`%TEMP%\mcp045-evidence\`、`%TEMP%\mcp046-evidence\` |

本批改动的文件与 sha256（两个 `.ps1` 均**纯 ASCII**：逐字节非 ASCII = 0；`Parser::ParseFile` `parse-errors=0`）：

| 文件 | sha256 |
|---|---|
| `scripts/mcp010_b2_observation_evidence.ps1` | `6ef0a2d094e21c109184717f7ced59854abadf2504daa76b488fab75aacb9cde` |
| `scripts/mcp014_m3_evidence.ps1` | `a167cbe2440e15dc00ca346477f103e80663e4f273d4941a01c19f987fefe967` |

---

## 1. section 1 — `mcp010` 的 4 条 TASK-010 期硬编码不变式改为**派生**

### 1.1 改法（照 `accept_m1.ps1` 的办法，不是改数字）

新增 `Get-DerivedExpectations`：唯一事实源是五个 per-batch manifest
（`tool-groups.json`、`-b2`、`-b3`、`-b4`、`-b5`）里 `implemented: true` 组的 `tools` 的**并集**，
每个工具的 `scope` 取 `docs/tool-rename-map.json`；契约成员资格取 `docs/tools_list.renamed.json`。
产出 `Union / Duplicates / Foreign / UnknownScope / Editor|Both|GameScope / Editor|GameEndpoint / EditorOnly|GameOnly`。
**缺一个 manifest 直接 throw**——跳过它会静默缩小期望集合，正是这套派生要防的失效模式。

### 1.2 逐条前后对照

| 相位 | 旧断言（TASK-010 期字面量） | 新断言（派生） | 旧实测 | 新实测 |
|---|---|---|---|---|
| `count` | `count_implemented_union_is_48`：`union==48 且 B1==41 且 B2==7` | 拆为 `count_every_implemented_tool_is_in_the_contract`（`foreign==0`）+ `count_every_implemented_tool_has_a_known_scope`（scope ∈ editor/both/game）+ `count_manifests_are_disjoint`（**五**个 manifest 的任意组两两不重叠，且 implemented 名不在两个 manifest 里） | 红（union 66） | **PASS** |
| `count` | `count_scope_split_is_17_23_8` | `count_scope_split_matches_the_rename_map`：`editor+both+game == union`（分区必须**覆盖**并集；scope 拼错会同时掉出两个 scope 列表并**偷偷出现在两个端点**上） | 红（26/23/17） | **PASS**：`102 + 46 + 23 = 171 of 171` |
| `count` | `count_endpoint_expectations`：编辑器端点 `== 40` | `count_endpoint_expectations`：`editorEndpoint + gameEndpoint == union + bothScope`（both-scope 被两个端点各服务一次——旧字面量 40 就是这条算式在当年的取值） | 红（49） | **PASS**：`editor 148 + game 69 = union 171 + both 46` |
| `scope` | `scope_the_editor_game_split_is_exactly_the_scopes`：`editorOnly==17 且 gameOnly==8 且 B2 的 8 个 game 工具都在 gameOnly 里` | 三条**集合相等**（`Test-SameNameSet`，case-sensitive、无序）：`scope_editor_endpoint_serves_exactly_the_derived_set`、`scope_game_endpoint_serves_exactly_the_derived_set`、`scope_the_editor_game_split_is_exactly_the_scopes`。活端点与派生集合逐名比对，**计数相同但成员换了**也会红 | 红（102/23） | **PASS** |

**没有动的两条**（不在任务书点名的 4 条内，且它们不是「不变式」而是「结构校验」/「冻结快照」）：

- `count_b2_manifest_is_25_tools`：B2 manifest 的**工具总数**（与 implemented 无关），manifest 文件本身由
  `check_tool_groups.py --batch B2` 按 sha256 冻结；保留。
- `count_manifests_are_disjoint`：保留并**加强**（从「B1/B2 全组重叠」扩到「五个 manifest 全组两两重叠 + implemented 名重复」）。

另外顺手把 `-Phase count` 从「B1 + B2」扩到跑全五个批次的 checker
（`--batch B2/B3/B4/B5` + `--check-completeness`），因为派生现在读全部 manifest ——
在一个没人校验过的 manifest 上做绿色派生是没意义的。

### 1.3 复跑证据（真实输出，`%TEMP%\task048-final-gates\`）

```
$ powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp010_b2_observation_evidence.ps1 -Phase count
manifests implemented: tool-groups.json=41, tool-groups-b2.json=25, tool-groups-b3.json=40, tool-groups-b4.json=7, tool-groups-b5.json=58
implemented union    : 171 tool(s)
scope split          : 102 editor-scope + 46 both-scope + 23 game-scope
editor endpoint 9888 : 148 tool(s) (union minus the 23 game-scope tools)
game endpoint   9889 : 69 tool(s) (union minus the 102 editor-scope tools)
only-lists           : editor-only 102, game-only 23
[PASS] count_manifests_are_disjoint :: names claimed by two manifests (any group) = 0 []; implemented names carried by two manifests = 0 []
[PASS] count_b2_manifest_is_25_tools :: B2 manifest tool count = 25
[PASS] count_every_implemented_tool_is_in_the_contract :: implemented names absent from the 171 entry contract = 0 []
[PASS] count_every_implemented_tool_has_a_known_scope :: implemented names whose rename map scope is not editor/both/game = 0 []
[PASS] count_scope_split_matches_the_rename_map :: 102 editor + 46 both + 23 game = 171 of 171 implemented tool(s)
[PASS] count_endpoint_expectations :: editor 148 + game 69 = union 171 + both-scope 46
=== phase count: 12/12 checks passed ===        (exit 0)
```

```
$ powershell ... mcp010_b2_observation_evidence.ps1 -Phase scope
[PASS] scope_editor_endpoint_serves_exactly_the_derived_set :: live 9888 = 148 tool(s), derived = 148; live_only=[] derived_only=[]
[PASS] scope_game_endpoint_serves_exactly_the_derived_set :: live 9889 = 69 tool(s), derived = 69; live_only=[] derived_only=[]
[PASS] scope_the_editor_game_split_is_exactly_the_scopes :: editor-only live=102 derived=102 (live_only=[] derived_only=[]); game-only live=23 derived=23 (live_only=[] derived_only=[])
[PASS] guard_user_port_9877 :: listening=False pid_before=-1 pid_after=-1 ours=False same_pid=True asked_by_us=False classification=environment_fact_no_listener_before_or_after our_pids=[62552,71840] our_ports=[0,9888,9889] our_command_lines=3
=== phase scope: 15/15 checks passed ===        (exit 0)
```

**改前/改后退出码**：`scope` 从 **12/13 → 15/15**（exit 0），`count` 从 **4/7 → 12/12**（exit 0）。
派生的数字与 `accept_m1.ps1` 独立给出的 `148 / 69, editor-only 102, game-only 23` **完全一致**，
并与 `check_tool_groups.py --check-completeness` 的 `66 + 105 = 171` 相容。

---

## 2. section 2 — `mcp014_m3_evidence.ps1:183` 的一行缺陷

### 2.1 改了什么

TASK-028 把本地 `Write-Utf8NoBom` 换成共享守卫 `mcp_import_guard.ps1` 的 `Write-McpUtf8NoBom` 时，
**漏改了一个调用点**。本批只改这一行（外加一段说明为何改的注释）：

```diff
-    Write-Utf8NoBom -Path $bodyFile -Text $Json
+    Write-McpUtf8NoBom -Path $bodyFile -Text $Json
```

`mcp014` 只 dot-source 了 `mcp_import_guard.ps1`，其中**没有**旧名字（`grep '^function '` 只有
`Write-McpUtf8NoBom` / `New-McpScratchProject` / `Import-McpProject`），因此旧名字必然 `CommandNotFound`
→ `-Phase m3` 在 `m06` 之后中止（MILESTONES-CLOSURE §3.3 的原记录）。

### 2.2 mono 二进制：**必须重建**（不是复用）

任务书允许「mono 若仍在且 `--version == HEAD` 则复用」。开工时实测
`bin\godot.windows.editor.x86_64.mono.console.exe --version = 4.8.dev.mono.custom_build.595607336`，
而 HEAD = `019c4b019` —— **不相等**，所以按任务书**串行重建 mono**
（`D:\Anaconda\Scripts\scons.exe platform=windows target=editor module_mono_enabled=yes -j8`，
日志 `%TEMP%\task048-logs\mono_build.log`，`scons: done building targets.` / `INFO: Time elapsed: 00:01:41.07`）。
重建后 mono `--version = 4.8.dev.mono.custom_build.019c4b019` == HEAD。
构建期间没有第二个 scons、没有引擎在跑（D62 假编译错误的两个前提都成立）。

### 2.3 完整复跑 `-Phase m3` 的真实结果：**18/20，exit 1**

命令（日志 `%TEMP%\task048_mcp014_m3.log`）：

```
$ powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp014_m3_evidence.ps1 `
      -Phase m3 -Engine bin\godot.windows.editor.x86_64.mono.console.exe
```

**脚本缺陷已消除**：它不再在 `m06` 中止，而是**跑完整个 m3 相位**（m01..m24），
`m01` SDK `4.8.0-dev`、`m02` 4 个本地 nupkg、`dotnet build` exit 0、`m04` 程序集、`m05` mono `--version`、
`m06` 两个端点起得来、C# 状态经 MCP 读回、`m22` 活 schema `required=[]` 等均 PASS。
剩下 **2 条红**（`18/20 checks passed`）：

```
[FAIL] m09_mono_tool_counts_49_and_40 :: under mono: tools/list = 148 on 9888 (editor, expected 49) and 69 on 9889 (game, expected 40)
[FAIL] m23_guard_user_port_9877 :: pid_before=-1 pid_after=-1 (the user's Godot 4.7.1-mono editor was never touched)
```

**这两条都不是回归，是本次才第一次被跑出来的陈旧不变式**（原因：旧缺陷让脚本在 `m06` 就停了，
m09/m23 从未执行过）：

- `m09`：字面量 `49/40` 是 TASK-014（M3）时代实现集的大小。活的 mono 端点给出 **148/69**，
  与该 HEAD 上**派生**出来的期望**完全相等**（§1.3，且 `accept_m1` 门⑤ 与 `mcp010 -Phase scope` 各自独立给出同一组数字）。
  → 属 MILESTONES-CLOSURE §3.2 的 **(A) 时代陈旧的不变式**，与 `mcp010` 那 4 条同一类。
- `m23`：谓词是 `pid_before -eq pid_after -and pid_before -gt 0`，本环境 9877 无监听者
  （`pid_before = pid_after = -1`）→ 恒 False。→ 属 §3.1 的 **(C) 环境事实**，
  与 TASK-047 已对齐的 `mcp010/mcp019/mcp027` 同一类；「我们没占用 9877」这条**真**不变式并未被违反
  （m24 的 `port_9888_released` / `port_9889_released` 均 PASS，收尾复核也确认无监听）。

### 2.4 为什么**没有**顺手修 m09/m23 —— 显式声明

任务书 section 2 把这个交付明确限定为「**一行缺陷**」，且 TASK-047 的 §3.3 明确记载
「改 `mcp014` 的 9877 处理是替决策层扩大范围」。同一脚本的 `-Phase gate2`（非 mono 相位）
还带着**同源的** `g06_tool_counts_49_and_40`、`g26_guard_user_port_9877`（本批未跑 gate2 相位，
故未复现，但源码逐字同形）。把这四条一并改成派生/共享端口守卫并不是难题——
**困难的是判断它是否在授权内**，而这属于决策层。因此：

> **本批只修任务书授权的那一行，m09/m23/g06/g26 原样保留，只登记 + 给出证据与归因。**
> `MILESTONES-CLOSURE.md` §5.1 已把这条作为「TASK-048 发现，未修」的独立条目登记，
> 并建议决策层把它们并入 section 1 已经建立的「派生 / 共享端口守卫」处理。

---

## 3. section 3 — 补跑未跑的门批次与证据脚本（真实结果）

三个聚合器**各一个大脚本、内部步骤全部串行**；三条捕获/成本脚本也**逐条串行**。
任何时刻只有一个引擎进程、只有一个 scons。三个聚合器的 `summary.txt` 各自声明
`binary --version: 4.8.dev.custom_build.019c4b019` 与 `git HEAD: 019c4b019`。

### 3.1 三个门批次聚合器

| 脚本 | 退出码 | 步骤退出码统计 | 汇总日志 |
|---|---|---|---|
| `scripts/mcp041_gates.ps1` | **exit 0** | **17/17 步骤 EXIT 0** | `%TEMP%\mcp041\gates\summary.txt` |
| `scripts/mcp042_gates.ps1` | **exit 0** | **19/19 步骤 EXIT 0** | `%TEMP%\mcp042\gates\summary.txt` |
| `scripts/mcp043_gates.ps1` | **exit 0** | **28/28 步骤 EXIT 0** | `%TEMP%\mcp043\gates\summary.txt` |

关键计数（原文行）：

| 步骤 | 真实输出 |
|---|---|
| 门③（三批各一次） | `[doctest] test cases: 293 \| 293 passed \| 0 failed \| 1429 skipped`；`assertions: 21431 \| 21431 passed \| 0 failed`；`Status: SUCCESS!` |
| 门④（三批各一次） | `1719 \| 1719 passed \| 0 failed \| 3 skipped`；`assertions: 445713 \| 445713 passed \| 0 failed`；`Status: SUCCESS!` |
| 门⑤（三批各两次 = 6 次） | 均 `22/22 cases passed`；`implemented tools : 171 / contract 171`；`process split : editor endpoint 148 tool(s), game endpoint 69 tool(s), editor-only 102, game-only 23` |
| 门① 契约子集 | `3/3 checks passed`；`implemented_union=148 tools (editor endpoint) / 69 tools (game endpoint)`；mcp043 另跑四个分组（`editor_write_scene_editor` / `project_setting_write` / `project_autoload_write` / `editor_input_simulation`）均 `3/3` |
| 门⑥a 收窄点 | `scanned : 75 narrowing point(s) in 16 file(s)`；`pinned : 75`；`coverage : 17 declared spelling(s)`；exit 0（`10 pinned line number(s) drifted` 是 §3.5 的信息性附注） |
| 门⑥c 覆盖探针 | `101/101 checks passed; … (log sha256=7e2a773f9f4bd483018830420b4fd7cdb22d3997f54e0bd7707696b2b3af7bd3)` —— 与 MILESTONES §2 记录**同 sha** |
| `gate2_wire_evidence` / `gate2c_task041_evidence` / `gate2e_task041_evidence` | `32 checks, 0 failed` |
| `gate2_rewrite_and_honesty_evidence` | `30 checks, 0 failed` |
| `gate2b_port_guard_probes` | `21 checks, 0 failed` |
| `regress_mcp032` | `TASK-032 evidence: 38 checks, 0 failed` |
| `regress_mcp033` | `74/74 checks passed`（summary sha256 `37b18a3e…`） |
| `regress_mcp034` | `113/113 checks passed`（summary sha256 `0e510e7b…`） |
| `regress_mcp035` | `66/66 checks passed`（summary sha256 `eda6d7b9…`） |
| `regress_mcp036` | `58/58 checks passed`（summary sha256 `b941cdb4…`） |
| `regress_probe037` | `PROBE037 base: 39/39 checks passed` |
| `regress_mcp040_probes` | `47 checks, 0 failed`（labels `task041/042/043`） |
| `regress_mcp040_racing` | `35 checks, 0 failed` |
| `mcp043 gate2f_snapshot_before_contract` | `806d5396b:…tools_list.renamed.json sha256=c844ec8af9ef00d2e6ec7008c9806b3e2b16757e78794d3ccca0704edf844256 (expected c844ec8af9ef…)` |
| `mcp043 gate2a_description_evidence` | `RESULT 16 checks, 0 failed`；`143 untouched live descriptions sha256=44f12a29…` 与契约侧同 sha；`tools/list sha256=23f3bd6b…` |
| `mcp043 gate2b_reload_plugin_probe` | `RESULT 14 checks, 0 failed`（`P25b_second_reload_still_succeeded`，中文 message 原样返回） |
| `mcp043 gate2g_contract_diff` | `problems = 0`；`changed tools = editor_add_input_action, editor_reload_plugin, project_add_autoload, project_remove_autoload, project_set_setting`；`overrides 18 -> 23` |
| `mcp043 gate2h_registration_literals` | `failures = 0`（4 条工具字面量 `EQUAL`） |
| `mcp043 gate2i_group_lookup` | `rows=5` |

### 3.2 `mcp044` / `mcp045` / `mcp046`

| 脚本 / 相位 | 退出码 | 关键计数 |
|---|---|---|
| `mcp044_capture_evidence.ps1 -Phase editor` | **exit 0** | **`40/40 checks passed`**；三个视口帧互异 `2d=2978x1793 3d=2978x1790 editor=3840x2054`；`duration_ms` off 中位数 `0.0` → every_call `7.0 ms`；往返 off `0.0241s` / back-to-back `0.1017s` / spaced `0.0325s` |
| `mcp044 -Phase headless` | **exit 0** | **`8/8 checks passed`**（`unavailable` 判决是**一行**而不是空白图） |
| `mcp044 -Phase game` | **exit 0** | **`9/9 checks passed`** |
| `mcp044 -Phase diff-image` | **exit 0** | **`5/5 checks passed`** |
| `mcp045_pixel_compare_cost.ps1 -Label post` | **exit 0** | **`15/15 checks passed`**；`changed=True changed_pixels=106800 total_pixels=5339554 ratio=0.0200016705515105`（与 TASK-044 的数一致）；第二次同值写入 `changed=False changed_pixels=0`；`png_encoding_expected=fast`；`pair_before` sha `c2d7a1bf…` / `pair_after` sha `45160828…`；往返 off `0.0234s` / back-to-back `0.1012s` / spaced `0.0321s` / diff 工具 `0.3339s` |
| `mcp046_capture_encode_cost.ps1 -Label post` | **exit 0** | **`23/23 checks passed`**；scale1 PNG `113929 / 112102 B`，scale2 `29072 / 29064 B`；`paid_back_to_back_ratio_scale2_over_scale1=0.906`；`curl_round_trip_every_call_scale1_back_to_back` 中位数 `0.0997s` |

三者都在**窗口化**（非 `--headless`）编辑器/游戏进程上跑（`mcp044` 的 editor/game 相位需要真 framebuffer），
在本机可以正常起窗口并完成；9877 守卫均 PASS（`pid_before=-1 pid_after=-1`）。
`mcp044` 的 `editor` 相位在各 phase 上各写 `summary-<phase>.txt`，四条都落盘。
**没有任何一条「跑不起来」**——§4.4 只剩「hof-rs 冒烟」与「clean 位级可复现」两条本来就不由本模块负责的项。

### 3.3 仍**未跑**的（不写成「通过」）

| 项 | 状态 | 理由 |
|---|---|---|
| M5 的「hof-rs 切端点 + 真实 T=1 冒烟」 | **未跑** | 属 hof-rs 侧（`F:\moonbit-hof-rs`，本模块只读） |
| clean 全量重建的位级可复现性 | **未验** | 与 `ACCEPTANCE.md` §M0 的 U1 同。**本批实测旁证**：同源码两次 `build_local -Force` 产出的 console 二进制 sha256 不同（`e4060b0f…` → `690807df…`），即本工具链下重建**不是位级可复现**；不影响「同命令 → exit 0 → `--version` == HEAD」这条判据 |

---

## 4. 门与门⑥（任务书 section 4）

`mcp041/042/043` 已各跑一遍门③/④/⑤/⑥a-c。为让证据绑定**最终**产物，本批又在
`build_local.cmd -Force` 恢复非 mono 之后（`--version` == HEAD，sha256 `690807df…`）
独立复跑一次门①③④⑤⑥，退出码写进 `%TEMP%\task048-final-gates\summary.txt`：

```
STEP gate3_module_doctest EXIT 0
STEP gate4_full_doctest EXIT 0
STEP gate1_contract_subset EXIT 0
STEP gate6a_narrowing EXIT 0
STEP gate6b_narrowing_coverage EXIT 0
STEP gate6c_coverage_probes EXIT 0
STEP gate5_accept_run1 EXIT 0
STEP gate5_accept_run2 EXIT 0
STEP mcp010_count EXIT 0
```

| 门 | 最终二进制上的真实输出 | 结论 |
|---|---|---|
| ① 契约子集 | `3/3 checks passed`；`implemented_union=148 (editor) / 69 (game)`，契约 171 | PASS |
| ③ 模块 doctest | `293 / 293 passed \| 0 failed \| 1429 skipped`；`assertions: 21431 \| 21431 passed \| 0 failed` | PASS（与 §2/REPORT-046 基线逐字相同，未增加） |
| ④ 全引擎回归 | `1719 / 1719 passed \| 0 failed \| 3 skipped`；`assertions: 445713 \| 445713 passed \| 0 failed` | PASS（0 failed；passed 未变） |
| ⑤ 独立验收 ×2 | 两次 `22/22 cases passed`，两次的 22 行 `[PASS]` 清单 **`Compare-Object` 为空** | PASS |
| ⑥a 收窄点 | `scanned=75  pinned=75  coverage: 17 declared spelling(s)`，exit 0 | PASS |
| ⑥b 覆盖声明 | `--coverage` exit 0 | PASS |
| ⑥c 覆盖探针 | `101/101 checks passed`，log sha256 `7e2a773f…`（与上批同 sha，跨批次可复现） | PASS |

> 门⑥ 仍只是**三道腿之一**（机器检查 + 代码审查 + 行为证据）：本批**没有新增/修改任何收窄代码**
> （§5.1 证明 `tools/**` 零改动），因此「新增点 × 闸门 × 证据」清单为空集——这是可核对的，
> 不是省略。

---

## 5. 纪律证据

### 5.1 「不改模块实现、不改契约」

```
$ git diff --stat -- modules/mcp_server/tools tests
（空输出）
$ echo exit=$?
exit=0
```

`tools/**` 与 `tests/**` **逐字节零改动**；契约 `docs/tools_list.renamed.json`、
映射 `docs/tool-rename-map.json`、组清单 `docs/tool-groups*.json`、生成器均**零改动**。
本批的工作树只有两个 `.ps1` 被修改（§0 表）——`git status --porcelain`：

```
 M modules/mcp_server/scripts/mcp010_b2_observation_evidence.ps1
 M modules/mcp_server/scripts/mcp014_m3_evidence.ps1
?? .graphifyignore
?? build-m0.cmd
?? graphify-out/
?? install-deps-m0.cmd
?? modules/mcp_server/docs/tasks/TASK-048-derived-invariants-and-battery.md
?? modules/mcp_server/docs/tasks/TASK-049-object-subpath-closure.md
```

### 5.2 构建纪律

| 序 | 命令 | 结果 |
|---|---|---|
| 1 | `modules\mcp_server\scripts\build_local.cmd -Force`（**从 cmd 启动**，`tests=yes`，不抑制输出） | exit 0；`scons: done building targets.` / `INFO: Time elapsed: 00:00:37.57`；`--version` → `4.8.dev.custom_build.019c4b019` == HEAD |
| 2 | `D:\Anaconda\Scripts\scons.exe platform=windows target=editor module_mono_enabled=yes -j8`（串行） | exit 0；mono `--version` → `4.8.dev.mono.custom_build.019c4b019` == HEAD |
| 3 | `build_local.cmd -Force`（恢复非 mono） | exit 0；`INFO: Time elapsed: 00:01:46.15`；`--version` 重新校验 == HEAD |

三次**串行**：每次之间没有第二个 scons、没有引擎在跑。`build_local.cmd` 用 `%TEMP%\mcp_server_build_local.log`
（它把 scons 输出落进日志、并回填 `EXIT_CODE=`，不是丢弃输出）。

### 5.3 端口 / 证据 / 外部约束

- **9877 从未被占用、杀、重启**：唯一使用它的动作是 `Get-ListenerPid` 只读 `netstat`；
  每次运行的守卫行都是 `classification=environment_fact_no_listener_before_or_after`。
  收尾复核：9877/9888/9889 均无 LISTENING。
- 只用 9888（编辑器）/ 9889（游戏）。每个脚本只杀**自己启动的** pid。
- 证据一律 `curl.exe -s -o <file>` 落盘（脚本内部实现，本批未改这条纪律），
  本次读取的汇总都来自盘上的 `summary.txt` / `summary-*.txt`。
- **未 push**；只有本地提交。
- `.ps1` **纯 ASCII**（非 ASCII 字节 = 0）；两文件 `parse-errors=0`。

---

## 6. deviations（与任务书/手册的偏离，逐条）

1. **`-Phase count` 的覆盖范围从 B1+B2 扩到全五批**（多跑 `--batch B3/B4/B5` 与 `--check-completeness`）。
   理由：派生现在读全部 manifest，不校验它们会让派生建立在一个没人验证过的输入上。成本 ~秒级。
2. **`count_manifests_are_disjoint` 加强**（B1/B2 全组重叠 → 五 manifest 全组两两重叠 + implemented 名重复）。
   理由：与 `-Phase count` 的新覆盖面一致；是加强不是削弱。
3. **`count_implemented_union_is_48` / `count_scope_split_is_17_23_8` 被删除并替换**（而不是改成新数字）。
   理由：任务书要求「不许只改数字」；一个钉住计数的断言在派生语境下是空的（期望与实际同源）。
   替代它的是三条**能真的失败**的结构断言（契约成员、已知 scope、分区覆盖、端点算式）。
4. **`mcp014 -Phase m3` 的结果是 `18/20`、exit 1**，任务书只说「完整复跑」没说必须绿。
   两条红（m09/m23）是**本次才第一次被执行**的陈旧不变式，不是回归。**未修**，理由见 §2.4。
   这是本报告最需要决策层裁决的一点。
5. **mono 二进制是重建的，不是复用的**：开工时 mono `--version` 是 `595607336` ≠ HEAD `019c4b019`，
   按任务书条件应重建（§2.2）。
6. **额外做了三次构建中的第 3 次**（恢复非 mono），以及一次「最终二进制」的门复核（§4）。
   理由：门必须绑定最终产物；MILESTONES §0.3 的序 3 就是这条纪律。
7. `TASK-049-object-subpath-closure.md` 是本批开工前就存在的**未跟踪**任务书（决策层给下一个任务的输入），
   本批**不动它**，也不提交它。

---

## 7. commits

| sha | 一行说明 |
|---|---|
| `cef846a418fddeabe764ef0d65b5fde48ca12c1d` | `fix(mcp_server): derive mcp010's TASK-010 invariants and repair the mcp014 m3 call site (TASK-048)` |
| （纯文档，本报告与 `MILESTONES-CLOSURE.md`） | `docs(mcp_server): REPORT-048 + MILESTONES-CLOSURE section 4 reruns (TASK-048)` |

**D86 锚点**：上表第一条 `cef846a418` 是本批脚本改动落地的提交；§1/§3/§4 的全部命令都在
**HEAD `019c4b019`**（即该提交的父提交树上、以 `--version == 019c4b019` 的二进制）跑出。

---

## 8. blockers

无**阻塞**项。两处需要决策层裁决（不阻塞本批交付）：

1. `mcp014` 的 m09/m23（以及 gate2 相位的 g06/g26）——四条同源陈旧不变式，
   建议并入 TASK-048 section 1 已建立的「派生 + 共享端口守卫」处理（§2.4）。
2. `mcp027` 的 `D8_whole_resource_bag_round_trips` 仍未修（TASK-027 议题，MILESTONES §3.4）。

## 9. next_step_recommendation

1. 若接受 §2.4 的归因，下一批把 `mcp014` 的 m09/m23/g06/g26 改成
   （a）端点工具数**从 manifest + rename map 派生**、（b）9877 判定走
   `scripts\mcp_port_guard.ps1` 的 `New-/Register-/Complete-` 三段式（与 TASK-047 对三个脚本的做法完全一致），
   然后 **`-Phase gate2` 与 `-Phase m3` 各完整复跑一次**（本批只跑了 m3，gate2 未跑）。
2. 收尾 `mcp027` 的 D8（资源包按名含 `/` 的属性），它是 MILESTONES 里最后一条与模块行为有关的已知红。
3. 若要真正的「171/171 全绿收口」，可在完成 1/2 后重跑本报告 §3 的六个脚本作为一次封存。
