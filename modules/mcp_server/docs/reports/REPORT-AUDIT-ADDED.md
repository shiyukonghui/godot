# REPORT-AUDIT-ADDED — 独立验收：**新增的 4 个工具 + 契约扩张机制**

> 验收方：**独立验收子代理**（未参与实现，未采信任何 `REPORT-*`）。
> **D86 提交锚点**：`da657ea1fca4b426cd834f8904c2087334686d48`（`git rev-parse HEAD`，审计全程未变；
> `git log -1` = `docs(mcp_server): TASK-055 ... and TASK-AUDIT-ADDED`）。下文**每一条结论**都是本验收方
> 在本提交上**自己重跑**得到的；凡引用规范文字均标 `文件:行`。
> **规范依据**：`DESIGN-DETAIL` §26/GDR-28（尤其第 5 条「新增不是降级通道」）、§20/§22/§23；任务书 `TASK-AUDIT-ADDED.md`。
> **环境事实**：`dotnet` SDK `9.0.100 / 9.0.300 / 10.0.300-preview.0.26177.108`；构建 `build_local.cmd -Force`
> （非 mono）exit 0，`--version` = `4.8.dev.custom_build.da657ea1f`；mono 变体
> （`scons platform=windows target=editor module_mono_enabled=yes tests=yes -j8`）exit 0，`INFO: Time elapsed: 00:01:36.63`，
> `--version` = `4.8.dev.mono.custom_build.da657ea1f`（与 HEAD 一致）。

---

## 0. verdict

| 分类 | verdict | 一句话 |
|---|---|---|
| 机制自洽 | **pass** | `ADDED_TOOLS` 为第三张表、幂等、无手改；171 条移植条目**逐字未变**，新增**恰为 4 条**，`_meta` 只动预期字段 |
| 对等门 | **pass** | 实时 `tools/list` 解析：9888=152 / 9889=72，并集 = 契约 **175**，逐条 name/description/inputSchema 逐字相等，scope **双向零泄漏**，跨端点 `-32601` |
| 四个新工具 | **fail** | 3 个通过；`project_validate_scripts` 对 `language_unavailable` 条目**发布了 `"valid": false`**（见 D1） |
| M-5 `sample_stride` | **pass** | 默认路径无新键、与显式 `sample_stride:1` **逐字节相同**；步长语义/点数/字节正确；`0`/负数/非整数 → `-32602` |
| 顺手性 | **pass** | 10 工具跨工具链、**字符串手术 0 次**，含「从零建 C# 工程 → 写文件 → 写脚本 → 构建 → 校验」闭环（真实产物 sha256） |
| 工程门 | **pass** | 13 个门步骤全 exit 0；门③327/0、门④1753/0、门⑤两跑 PASS 清单一致、门⑥ 三段式（101/101 探针、树字节还原） |
| 端口与孤儿 | **pass** | 9877 全程无监听（PID 恒为 `-1`）；只用 9888/9889 且收尾释放；无 godot/dotnet/MSBuild 孤儿；无 git 写操作 |

**总 verdict：`fail`** —— 唯一阻断项是 **D1**（一行 `valid` 字段的诚实性缺陷，规格明文禁止）。
其余全部通过；无架构级问题。修好 D1（并同步契约文字）后需**重跑本报告的 §四个新工具 / §对等门**两节。

**审计自身规模**：181 条自跑断言里 **12 条 FAIL**——**11 条来自我自己的首版脚本缺陷**（已在 §7.1 逐条声明并作废，
由更正后的脚本取代），**只有 1 条（v09）是产品缺陷**（即 D1）。另有 349 个证据文件（全部 sha256 在 `%TEMP%\audit-added\inventory.txt`）。

---

## 1. 机制自洽（GDR-28 §1/§2/§3/§7）

### 1.1 无手改 + 幂等（自己重生成）

```
certutil modules\mcp_server\docs\tools_list.renamed.json  -> 460004da50c6fa0a98bab07b04e6ca512297b6714ff8d9292b50ff5754aef027
python scripts\gen_renamed_contract.py --out %TEMP%\audit-added\regen1.json -> EXIT 0, output sha256 = 460004da…（同）
python ... \regen2.json                                                    -> EXIT 0, output sha256 = 460004da…（同）
fc /b regen1.json regen2.json      -> "no differences encountered"（幂等）
fc /b tools_list.renamed.json regen1.json -> "no differences encountered"（**跟踪文件不是手改的**）
重生成后再算跟踪文件 sha256 -> 460004da…（未动）
```

生成器自报：`input tools = 174 / output tools = 175 / added = 4 (project_build_csharp, project_write_text_file,
project_validate_scripts, editor_set_node_script_batch) / added verb extensions used = build, write /
overrides = 29 / self-checks = OK (lint 175/175, unique 175/175, disposition enum OK)`
（`%TEMP%\audit-added\gen1.log`）。`_meta.map_sha256 = 2f552719…` 与盘上 `tool-rename-map.json` 的 sha256
**逐字符相同**；`generated_from_sha256 = 8f8051c4…` 与 `F:\moonbit-hof-rs\tests\fixtures\mcp\tools_list.json`
的 sha256 相同（我各自 `certutil` 复核）。

### 1.2 结构化 diff：171 条逐字未变、新增恰为 4 条（不采信任何报告）

工具：`%TEMP%\audit-added\contract_diff.py`（按 `git show <rev>:docs/tools_list.renamed.json` 逐条**结构化**比较
name/description/inputSchema 与 `_meta`，**不做文本包含判断**）。三次 diff：

| diff | A → B | carried_over | changed | only_in_B | `_meta` 变化 |
|---|---|---|---|---|---|
| TASK-052（纯机制） | `d652a43a35`(171) → `c1f3385daf`(173) | **171** | **0** | `project_build_csharp`, `project_write_text_file` | 仅 `added_count(null→2)`, `added_tools(null→[…])`, `count(171→173)`, `generator_version(1.13.0→1.14.0)`；`map_sha256` **未动** |
| TASK-053 | `c1f3385daf`(173) → `96c1693d3d`(175) | 173 | 1（`running_game_get_node_property_samples` 的 `inputSchema`，即 M-5） | `project_validate_scripts`, `editor_set_node_script_batch` | `added_*`/`count`/`generator_version` + `overrides` 新增 `("inputSchema","monitor_properties")` |
| TASK-054 | `96c1693d3d` → `HEAD` | 175 | 2（`project_validate_script`、`project_validate_scripts` 的 **description**） | — | 仅 `generator_version(1.15.0→1.16.0)` |
| 汇总 | `d652a43a35`(171) → `HEAD`(175) | 171 | **2**（M-5 schema + 一句 C# 诚实性描述） | 恰为那 4 条 | 见上 |

→ 「**171 条移植条目逐字未变**」成立（`c1f3385daf` 处 changed=0），「新增恰为那 4 条」成立，
`_meta` 只动了预期字段，`map_sha256` 全程未动。证据：`diff_052.txt` / `diff_053.txt` / `diff_054.txt` / `diff_all.txt`。

### 1.3 两张 override 表与 `ADDED_TOOLS` 分离 + 四桶互斥 + `--added`

* 代码腿：`gen_renamed_contract.py:354` `DESCRIPTION_OVERRIDES`、`:596` `SCHEMA_OVERRIDES`、`:1191` `ADDED_TOOLS`
  是**三张独立的表**；`ADDED_TOOLS` 是 **list**（无 `old_name`），追加发生在 rename+override **之后**
  （`:1688-1717`），且 `validate_added()` 只用记录自带的 `channel/verb` 自校验，**不读**两张 override 表。
* 运行腿（`%TEMP%\audit-added\mechanism_probe.py`，PASS）：`count == len(result.tools) == 175` 且名字唯一；
  `result.tools[-4:]` **就是** `_meta.added_tools`（有序，`TAIL_OF_B` 逐字相同）；
  `added_names_recorded_as_overrides=[]`（新增**没有**被记成 override）；
  `docs/tool-groups-added.json` 的工具并集与 `_meta.added_tools` **双向相等**。
* 四桶互斥（自己跑，`%TEMP%\audit-added\groups.log`，`COMPLETENESS_EXIT=0`）：
  `contract entries = 175`、`B1/B2 = 66`、`added = 4`、`DERIVE 175-70 = 105`、
  `ASSERT 171 + 4 = 66 + 105 + 4: PASS`、`every one of the 175 contract names is in exactly one of the four buckets: PASS`、
  `B3/B4/B5 pairwise disjoint: PASS`、`disjoint from B1/B2 (66) and the added manifest (4): PASS`。
* `--added`（`ADDED_EXIT=0`）：4 组各自 `channel/scope/mutating/verb` 与名字派生一致；
  `manifest = contract _meta.added_tools, both directions: PASS (missing=0, foreign=0)`、
  `duplicates=0`、`every added verb is in the closed set or has a used verb_extensions record: PASS`（`build`/`write` 两条扩展都被使用，无 stale）。
* 既有五份批次清单 **sha 未变**：`git diff --stat c1f3385daf HEAD -- tool-groups{,-b2,-b3,-b4,-b5}.json` **输出为空**。

---

## 2. 对等门（GDR-28 §2；PLAYBOOK §7.4「禁止文本包含判断」）

两个端点的**原始 `tools/list` 响应体**由 `curl.exe -s -o` 落盘
（`plain-editor-toolslist.json` sha256 `deee6eb11dad2bb5f7d0e91fa5ac78659fbfbb19e051ec0e3db2384a3a6373cb`，152 条；
`plain-game-toolslist.json` sha256 `4563a7d7bf7d0c3f4a848ff0caa4f94c2ee023a04e12d651f06dbc628090edcb`，72 条），
再由 `%TEMP%\audit-added\analyze_parity.py` **解析 JSON 结构**（`name` 字段集合，绝不 `-match` 文本）：

```
EXPECTED editor=152 game=72 (editor_only=103 game_only=23 both=49)
LIVE editor count=152 duplicates=[]  not_in_contract=[] missing_from_live=[] unexpected_on_this_endpoint=[] scope_leak=[]
     verbatim(name/description/inputSchema) mismatches=0
LIVE game   count=72  duplicates=[]  not_in_contract=[] missing_from_live=[] unexpected_on_this_endpoint=[] scope_leak=[]
     verbatim(name/description/inputSchema) mismatches=0
UNION of the two endpoints = 175 ; UNION == contract names: True ; contract - UNION: []
INTERSECTION (served by both) = 49
ADDED project_build_csharp editor=T game=T scope=both ; project_write_text_file T/T both
      project_validate_scripts T/T both ; editor_set_node_script_batch T/F editor
PARITY_GATE=PASS
```

* 逐字门：**175 条中可见的每一条**都做了 `name`/`description`/`inputSchema`（`sort_keys` 规范化）比较，**0 处不符**。
* scope 双向零泄漏：编辑器端不含 23 条 game-only；游戏端不含 103 条 editor-only（`scope_leak=[]` 双向）。
* 跨端点 `-32601`：9888 上调 `running_game_get_scene_tree` → `-32601`（证据 `plain-editor-cross-running_game_get_scene_tree.json`）；
  9889 上调 `editor_get_scene_tree` → `-32601`。
* 独立旁证：仓库门脚本 `check_contract_subset.ps1` 由我**自己跑了 4 组**
  （`project_read_template` / `project_validate_scripts`(新增组) / `running_game_observation` / `editor_set_node_script_batch`），
  4/4 `checks passed`，每组都打印 `editor set : 152 tool(s)` / `game set : 72 tool(s)` 且 `guard_user_port_9877` PASS。

---

## 3. 四个新工具

### 3.1 `project_build_csharp`

| 要求 | 我的证据 | 结论 |
|---|---|---|
| ① 从零只用工具建 C# 工程并构建成功 | 全程只用工具：`project_write_text_file` 写 `res://Audit.csproj`（sha `622d53c6…`）→ `project_create_script` 写 `res://Program.cs` → `project_build_csharp{rescan:false}`：`jsonrpc code=0`，**payload `exit_code=0`**、`project_files=["res://Audit.csproj"]`、`exit_codes=[0]`、`timed_out=false`、`command="C:\Program Files\dotnet\/dotnet.exe build …\Audit.csproj -c Debug"`；产物 `bin\Debug\net9.0\Audit.dll` **4096 B**、sha256 `d3fa219146183358b24e43781c78324816650336ad809e6072f2eb48f9dcc28d`（我自己对盘上文件算的） | pass |
| ② 故意错的 `.cs` → 非零 + 诊断 | `project_edit_script` 写入缺少 `;`/`}` 的 `Program.cs` 后：**`exit_code=1`**、`timed_out=false`、`non_utf8_bytes=0`、`stdout_truncated=false`，捕获到真实诊断 `Program.cs(4,54): error CS1002` 与 `(4,55): error CS1513`（`B3_build_broken.response.json`） | pass |
| ③ 超时真的杀子进程 | 用 MSBuild `Exec`（`ping -n 300`）构造慢构建，`timeout_ms=2000`：`timed_out=true`、`killed=true`、`exit_code=-1`、`duration_ms=1601`、`effective_timeout_ms=2000`。**独立观察者进程**（`watch.ps1` 每 300 ms 记录）证实现场有 `dotnet:85220`，调用返回后该 PID **已消失**（`gone=dotnet:85220 still_alive=`），随后快照无任何 dotnet/MSBuild/VBCSCompiler | pass |
| ④ 能力缺失诚实拒绝（无 C# 后端） | 非 mono 构建上：`-32000`，`data.suggestion` = `Run the tool from a Godot build with the C#/mono module compiled in … (an official .NET build, or a local build with module_mono_enabled=yes)…`，**payload 为空**（无假成功） | pass |
| ④' 能力缺失诚实拒绝（无 SDK） | 把 `PATH` 里 5 条含 `dotnet` 的项全部剔除后启动 mono 引擎（同一进程内 `project_validate_scripts` 仍报 `category=unverifiable`，证 **C# 后端在、仅 SDK 缺**）：`-32000`，message `No 'dotnet' executable was found on PATH`，suggestion = `Install the .NET SDK (https://dotnet.microsoft.com/download) …`，payload 为空 | pass |
| ⑤ 并发/重入不留孤儿 | 全部 mono 测试结束后 `tasklist` 无 `dotnet.exe`/`MSBuild.exe`；`Get-Process` 快照 before/after 差集为空（`mono_no_orphan_dotnet_or_msbuild_process` PASS）；优先级/可重入由 timeout 用例覆盖 | pass |

### 3.2 `project_write_text_file`

| 要求 | 我的证据 | 结论 |
|---|---|---|
| ① 写 `.csproj`/`NuGet.config` 后读回 sha 与盘上一致 | `.csproj`：响应 `{path:"res://Minimal.csproj", bytes:159, sha256:971b42a9…, created:true}`，盘上 `Get-FileHash` = `971b42a9…`、159 B，**逐字节相同**；`NuGet.config`：响应 sha `576e9dd5…` = 盘上 sha；嵌套新目录 `res://sub/dir/Note.cfg` 也被创建（`bytes=10`） | pass |
| ② 四类拒绝 + 越界，且建议指向正确工具 | `project.godot` → `-32602` + `Use project_set_setting …`；`.tscn` → `-32602` + `Use project_create_scene_file …`；`.tres` → `-32602` + `Use project_create_resource or project_edit_resource …`；`.gd`/`.cs` → `-32602` + `Use project_create_script or project_edit_script …`；`res://../outside.txt` → `-32602` 「must not walk upwards with '..'」；`user://outside.txt` → `-32602`；`res://`（目录）→ `-32602`「must name a file」 | pass |
| ③ `overwrite:false` 命中已存在 → `-32000` + 点名 `overwrite:true`，且字节未变 | `-32000`，suggestion = `Pass "overwrite": true to replace the existing file, or choose another path`；前后 sha256 **同为** `971b42a9…`、字节同为 159（`w13`/`w14`） | pass |
| ④ 没有任何删除路径（代码腿 + 运行腿） | **代码腿**：`project_text_write.cpp` 内 `remove|delete|DirAccess|WRITE|erase` **零匹配**（grep）；写盘只经共享的 `publish_text_atomically` → `publish_file_atomically`（`tool_helpers.cpp:488-530`，它是**先备份→写临时→rename**，失败时把原字节放回，末尾只删自己造的 `.mcp-tmp*`）。**运行腿**：`overwrite:true, content:""` → **文件仍在且 0 字节**（不是被删）；`path:""`、`res://sub/` 均 `-32602`；项目内文件计数 before=4 / after=4，无任何文件消失 | pass |

### 3.3 `project_validate_scripts` —— **本节含 D1**

| 要求 | 我的证据 | 结论 |
|---|---|---|
| 批量一致性 + 逐文件分类 | `paths=[valid.gd, broken.gd, legit.cs, broken.cs]` → `count=4, valid_count=1, invalid_count=1, unavailable_count=2, unverifiable_count=0`，**四类计数之和 == count**；`ok` 项 `valid:true`；`invalid` 项 `valid:false` + `error_text=ERR_PARSE_ERROR` | pass |
| 语言不可用不得记成 `valid:false` | **`language_unavailable` 条目的线上字节里带 `"valid": false`** —— 见 D1 | **fail** |
| `paths` 越界 → `-32602` | `res://../escape.gd` → `-32602`（suggestion 含 `..`）；`paths:[]` → `-32602`；缺失文件 → `-32001` | pass |
| 与单数工具口径一致 | `valid.gd`：单数 `valid:true` / 批量 `ok+valid:true`；`broken.gd`：单数 `valid:false` / 批量 `invalid+valid:false`；`legit.cs`：单数 `-32000`（点名 mono 构建）/ 批量 `language_unavailable` + 同句 suggestion；mono 构建上 `Program.cs`：单数 `-32000` / 批量 `unverifiable` + `valid:null` | pass（除 D1 的字段问题） |
| 只读（不改工程） | 工具文件内 `WRITE|remove|store_|save|DirAccess` **零匹配**；运行腿：调用前后项目内 10 个文件 sha 全部不变、无文件消失 | pass |
| 有界/可声明 | `limits.max_scripts=64`、`truncated/dropped` 字段存在；`errors_only:true` → `returned=1 < count=2` 且回显 `errors_only` | pass |

### 3.4 `editor_set_node_script_batch`

读回见证用**落盘 `.tscn`**（模块自己的 `editor_get_node_properties` 按设计拒绝按名读 `script`）与**其 sha256**：

| 要求 | 我的证据 | 结论 |
|---|---|---|
| 全成功 | `{script_path:res://scripts/two.gd, node_paths:[A,B]}` → `status=ok, count=2`，`attached[]` 每项 `attached:true`，保存后的 `.tscn` 里 `A`/`B` **都**带 `res://scripts/two.gd` | pass |
| `keep_existing:true` 跳过并计入 `skipped[]`，不得覆盖 | `{…, node_paths:[A,B,C], keep_existing:true}` → `skipped=2`（A、B）、`count=1`（C），`skipped[].reason = "the node already carries a script and 'keep_existing' is true"`、`skipped[].previous_script_path=res://scripts/two.gd`、`skipped:true`；`.tscn` 证实 **A/B 未被覆盖**；全跳过时是 `code=0, count=0, skipped=2` 的**合法无操作** | pass |
| 逐节点读回（`attached` 真值） | 见上；另 `attached[].script_path == res://scripts/two.gd` 与磁盘一致 | pass |
| 全成功或全回滚（中间失败 → 回滚且树状态未变） | 用 `@abstract` 脚本构造拒绝：`-32000`，`data.batch = {status:"rolled_back", rolled_back:true, attached:[], count:0, on_error:"all_or_nothing", errors:[{index:0,node_path:"C",reason:"Node 'C' did not accept the script …"}], reverted:[]}`；**拒绝前后 `.tscn` sha256 完全相同**（`d588afa9…` → `d588afa9…`），逐节点脚本映射不变；`keep_existing:true` 下 `skipped[]` 也如实出现在拒绝信封里（`skipped=1, error_node=D`） | pass（但取回腿见 U1） |
| 越界/不存在 → `-32001` + 建议 | 缺节点 → `-32001`+`data.batch`；缺脚本 → `-32001`；空 `node_paths` / 缺必填 → `-32602`；指向 `.tscn` → `-32602`「is a PackedScene」；`res://../evil.gd` → `-32602` | pass |

---

## 4. M-5 `sample_stride`（`running_game_get_node_property_samples`）

| 要求 | 我的证据 | 结论 |
|---|---|---|
| 默认路径不新增字段 | 默认响应键集合 = `{frame_count, node_path, samples}`，**无** `sample_stride`/`observed_count`；默认与显式 `sample_stride:1` 的响应体 **逐字节相同**（1066 B，两边 sha256 都是 `96edb27b149816bdf2e9030104c4b902b60319caf2bb283ad2fb4ba62ea0b7a3`；为保证可比性该组用**静态属性** `z_index`/`name`） | pass |
| 显式步长：点数/字节正确 | `frame_count=60, frame_interval=1, sample_stride=10` → `sample_stride=10, observed_count=60, frame_count=6, samples=6`；`sample_stride=3` → `samples=20, observed_count=60`；响应体 5510 B → 716 B（13%）；默认与 `stride>1` 的**唯一键差** = `{observed_count, sample_stride}` | pass |
| `0` / 非整数 → `-32602` | `0` → `-32602`「must be at least 1」；`-5` → `-32602`；`1.5` → `-32602`「must be an integer, got float」；`"x"` → `-32602`「got String」 | pass |
| 与改动前二进制逐字节相同 | **不可复现**（无改动前二进制），见 U2；已给的是「默认 == 显式 1」逐字节 + 键差恰为文档所述两个键 | 部分确认 |

---

## 5. 顺手性（GDR-25 §23.1，零字符串手术链）

`t8_chain.ps1`（mono 构建，9888）：**10 步、跨 10 个工具、字符串手术 0 次**（每个参数都取自上一次响应里的**命名字段**，
没有 split/substring/regex/trim/拼接；脚本内 `$surgery=0` 断言）：

```
K1 project_create_scene_file{path:res://scenes/chain.tscn} -> path="res://scenes/chain.tscn"
K2 editor_open_scene{path : <K1.path>}                     -> path 回显同一串
K3 editor_add_node{...}                                    -> node_path="ChainChild"
K4 project_create_script{path:res://chain.gd}              -> path="res://chain.gd"
K5 editor_set_node_script_batch{script_path:<K4.path>, node_paths:[<K3.node_path>]} -> attached[0]={node_path:"ChainChild", script_path:"res://chain.gd"}
K6 editor_get_scene_tree{}                                 -> 子节点 path 集合中含 K5 返回的 "ChainChild"
K7 project_write_text_file -> res://Chain.csproj
K8 project_create_script   -> res://Chain.cs
K9 project_build_csharp    -> exit_code=0, project_files=["res://Chain.csproj"]   ← 闭环「从零建工程并构建」
K10 project_validate_scripts{paths:<K8.path>}              -> category=unverifiable, path 回显同一串
K11 产物 bin\Debug\net9.0\Chain.dll sha256 = 8d615196c7a7b97887d967abf7447262f2dd4bffdb0dc9d239c0cba7ad6d600a
```

---

## 6. 工程门、端口、纪律

* **门①**：见 §2（4 组脚本各 2/2 PASS，编辑器 152 / 游戏 72）。**门②**：每个新工具都给「成功 / 缺参 / 底层失败」
  三类真实请求响应（证据文件名见 §3 与 inventory），**并抽取 ≥3 个脚本**做批量校验（`v05` 一次校验 4 个脚本
  `valid.gd`/`broken.gd`/`legit.cs`/`broken.cs`，`v11` 无参扫描同样得到 4 个），加上 §5 活证据链。**门③**：327 cases / 327 passed / **0 failed**，
  23480 assertions / 0 failed。**门④**：1753 cases / 1753 passed / **0 failed**，447703 assertions / 0 failed。
  **门⑤**：`accept_m1.ps1` 连跑两次，两次各 22 行、PASS 清单 `Compare-Object` **完全一致**（含 `guard_user_port_9877`）。
  **门⑥**：`check_narrowing_points.py` exit 0、`--coverage` exit 0（打印已声明集合与未覆盖边界）、
  `mcp031_gate6_coverage_probes.ps1` **101/101 checks passed** 且声明「树已按字节还原」。
  另有 `--check-completeness` / `--added` exit 0（§1.3）。全部原始输出：`%TEMP%\audit-added\gates\*.log` + `summary.txt`。
* **端口**：`netstat` 起点与终点对 9877/9888/9889 都**无 LISTENING**；9877 我从未占用/杀/重启（每个阶段前后
  `Get-ListenerPid -Port 9877` 都是 `-1`：**用户编辑器在整个审计期间没有在跑**，故这是「真空满足」，见 U4）。
  我自己的端点只用 9888/9889，并在每个脚本的 `finally` 里停掉，结束时两个端口无监听。
* **孤儿**：结束快照无 `godot.windows.editor.x86_64.console.exe`、无 `dotnet.exe`、无 `MSBuild.exe`；
  我在 timeout 用例里额外清掉了由**我自己注入的** MSBuild `Exec` 启动的 `ping.exe` 孙进程。
* **无 git 写操作**：HEAD 起点=终点=`da657ea1fca4b426cd834f8904c2087334686d48`，`git log -1` 未变，
  `git stash list` 为空；`git status --porcelain` 仅剩既有未跟踪物（`.graphifyignore`、`build-m0.cmd`、
  `graphify-out/`、`install-deps-m0.cmd`）**加上本报告这一个新文件**。
* **构建纪律**：全程仅两次 scons，**串行**（非 mono → mono），均未抑制输出（日志 `%TEMP%\mcp_server_build_local.log`、
  `%TEMP%\audit-added\mono_build.log`）。mono 变体切换前按要求删了 `mcp_trace` 陈旧对象；
  mono 构建前后非 mono `console.exe` 的 sha256 都是 `62bc8bff…`（未被破坏）。
* **`.ps1` 纯 ASCII**：本次新建的 8 个脚本全部纯 ASCII；请求体一律 `ConvertTo-Json`，响应体一律 `curl.exe -s -o` 落盘 + sha256。

---

## 7. defects

| ID | 严重度 | 缺陷 | 证据（我自己的） | 规范依据 |
|---|---|---|---|---|
| **D1** | **blocking / moderate** | `project_validate_scripts` 对 `category="language_unavailable"` 的条目在线上**发布 `"valid": false`** | `v05_plural_mixed.response.json`（sha `8dd790dd2b7be478de342e5892b4efb577552c8c10a735f949f153ec21f8e853`）里该条目逐字为 `{"category":"language_unavailable","language":"cs","message":"… so the file was not parsed or compiled","path":"res://scripts/legit.cs","suggestion":"…","valid":false}`；实现落点 `tools/project_read_files.cpp:364`（`verdict.valid = false`）+ `tools/project_validate_scripts.cpp:168`（`entry["valid"] = p_verdict.valid`，仅 `unverifiable` 走 `Variant()`/null） | `TASK-053-added-tools-2.md:21-22`「单文件不可用 → 该项分类 `language_unavailable` + 说明，**不得**记成 `valid:false`」；`TASK-AUDIT-ADDED.md:30` 同款要求；`DESIGN-DETAIL.md:999-1000`（§26 第 6 条：缺能力必须诚实拒绝，**不得回显假数据**）；对照 TASK-054 已把 `unverifiable` 改成 `valid:null`（`DESIGN-DETAIL.md:1031-1032`），同一理由这里**不彻底** |
| D2 | minor（文档漂移，非机器校验） | `docs/tool-groups-added.json` 的 `source.entries` 仍写「generator **v1.15.0**」，而生成器已是 **1.16.0**（TASK-054 改了它所指向的那两条 C# 描述却未同步该字段） | `mechanism.txt:8-10`（自己跑出的版本比对）；`git diff --stat 96c1693d3d HEAD -- modules/mcp_server/docs/tool-groups-added.json` **为空** | `DESIGN-DETAIL.md:1020-1025`（新增清单是计数与归属的权威，其自述应自洽） |
| D3 | cosmetic | `project_build_csharp` 响应的 `command` 字段把可执行文件拼成 `C:\Program Files\dotnet\/dotnet.exe`（混合分隔符；实际执行成功） | `A3_build_csharp.response.json`（sha `cbc2d25f25ae58c67d4a572ff71461d86b7e962114abda6384c01a4a374b9acc`）；来源 `tools/project_csharp_build.cpp:452-457` 用 `path_join` 后拼字符串 | 无硬性条款；属可读性 |

> **不构成缺陷但必须登记的边界（D4）**：超时**确实杀掉直接子进程** `dotnet.exe`（有现场 PID 与消失证据），
> 但由 MSBuild `Exec` 任务派生的**孙进程**（我的探针用 `ping.exe`）会存活。任务书只要求「无孤儿 `dotnet`/`MSBuild` 进程」
> （满足），此点是**引擎 `OS::kill` 只作用于直接子进程**的既有边界，登记为风险 R1，不是本次新增工具的违规。

### 7.1 我作废的首版脚本缺陷（避免读者误读计数）

`counts.txt` 里 12 条 FAIL 中，**9 条**来自我自己的首版脚本，均已被更正后的 `t4c_batch.ps1`（23/23 PASS）取代：
`plain-batch-results.json` 的 c04/c08/c09/c12/c14（① `editor_get_node_properties` **按设计**拒绝按名读 `script` →
我的读回方式错了，改用落盘 `.tscn`；② 我假设「不兼容 native base 会被引擎拒绝」，实测**不会**（见 U1））；
`plain-batch2-results.json` 的 d13/d19/d21/d22/d23（期望值写错：拒绝前后我比错了取样点，以及同一构造函数不成立）。
另有 **1 条** `mono-results.json` 的 C3（我的进程观察者把文件写在循环结束后，被提前 Stop-Job → 观察为空），
已由 `t6c_timeout.ps1`（10/10 PASS，含 `dotnet:85220` 现场 PID）取代。**产品侧真正的失败只有 D1 一条。**

---

## 8. unconfirmed

| ID | 未确认项 | 我尝试过什么 / 为什么停下 |
|---|---|---|
| **U1** | `editor_set_node_script_batch` 的**取回腿**（`reverted[]` 非空：靠前的节点已落、靠后的节点被拒 → 把已落的取回）在**线上不可达** | 我构造了两种中间失败：(a) 不兼容 native base（`extends Control` 的脚本挂到 `Node2D` 节点）—— 实测**引擎接受**（`d09` 里落盘 `.tscn` 逐字含 `res://scripts/ctrl.gd`），故该构造不成立；(b) `@abstract` 脚本 —— 每个节点都拒绝，拒绝发生在**第一个** pending 节点，`applied` 为空 → `reverted:[]`。引擎里 `Object::set_script` 唯一的拒绝是 `ERR_FAIL_COND_MSG(s->is_abstract(), …)`（`core/object/object.cpp:1057`），**与节点无关**；`can_instantiate()==false` 在编辑器里会退化为 placeholder（`object.cpp:1069-1072`）因而**仍读回成功**。结论：取回代码存在（`editor_set_node_script_batch.cpp:294-317`，已做代码审查），但**没有输入能让「先落一个、再拒一个」**。已确认的是「全回滚信封 + 树状态逐字节未变」 |
| **U2** | M-5「默认响应与**改动前**二进制逐字节相同」 | 盘上没有改动前的二进制（`bin/` 被我的两次构建覆盖，git 不跟踪 `bin/`），TASK-053 报告里的 `sha eef36e62…` **我不采信也不复现**。我给的是同构建内的等价证明：默认 == `sample_stride:1` 逐字节（静态属性下确定性），默认无 stride 键，`stride>1` 仅多 `{observed_count, sample_stride}` 两个键 |
| **U3** | （已解决，留痕）`_meta.map_sha256` 是否等于盘上映射 | `certutil` 双算：`2f552719…` == `_meta.map_sha256`；`generated_from_sha256`=`8f8051c4…` == fixture 文件的 sha256。**该条已确认为真** |
| **U4** | 与**用户正在运行的** 9877 编辑器共存 | 审计全程 9877 无监听（每阶段 `pid_before = pid_after = -1`）。因此「未占用/未杀/未重启 9877」是**真空成立**，不是「与活跃监听者共存」的证明 |

---

## 9. risks

| ID | 风险 | 依据 |
|---|---|---|
| R1 | **超时不清理孙进程**：`OS::kill` 只作用于直接子进程；MSBuild 的 `Exec`/编译器 server 类孙进程会在超时后存活 | §3.1③ / D4：现场 `dotnet:85220` 消失，但 `ping:87420` 存活（我手动清掉）。真实工程里受影响的是被 MSBuild 目标代跑的外部命令 |
| R2 | **D1 的消费端影响**：只读 `valid` 字段的客户端会把「本构建没有该语言后端」读成「文件编译失败」，与 `unverifiable`（`valid:null`）处理不一致 → 同类假信息会沿调用链传播 | §3.3 / D1 |
| R3 | D2 的漂移会让未来读者以为当前契约由 1.15.0 生成，从而把 TASK-054 的两条描述改动漏出审计范围 | §7 D2 |
| R4 | 门⑥ 的保证仍是**有界拼写集合**（`--coverage` 自陈）；本次新增的 4 个工具里 `project_build_csharp`/`project_write_text_file` 有真实写值路径，报告已用「代码审查（每处写值点名经过的闸门）+ 行为证据」补足，但**这不是机器保证** | `check_narrowing_points.py --coverage` 输出；`DESIGN-DETAIL.md:721-757` |

---

## 10. next_step_recommendation

1. **修 D1（阻断项）**：`project_validate_scripts` 对 `language_unavailable` **不得**发布 `valid`；与 `unverifiable` 一致
   用 `Variant()`（JSON `null`）或**整个键不出现**，并让它与契约文字一致（在 `ADDED_TOOLS` 的该条目里写明
   「`language_unavailable` 也不给 `valid`」）。改动面极小：`tools/project_validate_scripts.cpp:168` 一处分支
   + `gen_renamed_contract.py` 的 `ADDED_TOOLS` 描述一句 + 重生成契约/指纹 + 相关 doctest。**派全新实现子代理**。
2. **修 D2**：把 `tool-groups-added.json` 的 `source.entries` 版本串更新到当前生成器版本（一行文档；若规范要求清单字段稳定，则改引用方式而不是数字）。
3. **可选的 D3**：`command` 字段用 `String::path_join`/正规化再拼，避免混合分隔符。
4. **修完后**由**新的**独立验收子代理**重跑本报告的 §2/§3.3/§6**（对等门 + 两个校验工具 + 门），
   并对 U1 保持「取回腿线上不可达」的声明；若决策者认为取回腿**必须**有线证据，则需要一条**能被构造**的失败输入
   （例如让 `apply_node_script` 的读回对某些节点失败），那是**规范/能力**问题，应先改规范再动人。
5. R1 建议登记为「已知边界」而非本任务缺陷；若将来要清孙进程，需走 `Job Object` 一类**进程组**语义，属架构选择。

---

## 附录 A：复核入口

* 复跑一切：`%TEMP%\audit-added\*.ps1`（`lib.ps1` + `t1/t3/t4c/t5/t6a/t6b/t6c/t7/t8` + `watch.ps1`）；
  分析器：`analyze_parity.py`、`contract_diff.py`、`mechanism_probe.py`、`count.py`、`inventory.py`。
* 原始证据：`%TEMP%\audit-added\evidence\`（每个请求/响应各一文件）、`%TEMP%\audit-added\gates\`（13 个门日志 + summary）、
  全部 349 个文件的 sha256 在 `%TEMP%\audit-added\inventory.txt`。
* 关键 sha256：契约 `460004da50c6fa0a98bab07b04e6ca512297b6714ff8d9292b50ff5754aef027`；
  9888 `tools/list` `deee6eb1…`；9889 `tools/list` `4563a7d7…`；非 mono 二进制 `62bc8bff…`；
  生成器脚本 `7f3dcd41…`；映射 `2f552719…`；fixture `8f8051c4…`。

## 附录 B：本次审计**没有**做的事

未修改任何被跟踪文件（唯一新增文件 = 本报告）；未 push、未 commit、未 stash；未装依赖；
未用 9877；**未把任何 `REPORT-*` 当作证据**：报告中的每个数字都来自我自己重跑的脚本/二进制，
`REPORT-052/053/054` 的片段只在检索过程中被工具顺带列过，**未被引用、未被采信**（D86 复测要求）。