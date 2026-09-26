# REPORT-AUDIT-ADDED-B — 独立验收（第二轮）：新增的 4 个工具 + 契约扩张机制

> **独立验收方**：未参与任何实现；**未采信任何 `REPORT-*`**。全部结论来自本人本次跑出的原始
> 请求/响应字节、日志、进程与文件哈希。
> 任务书：`docs/tasks/TASK-AUDIT-ADDED.md`；上一轮 `REPORT-AUDIT-ADDED.md` 的 D1 为本轮动因。

## 0. 提交锚点与基准（D86）

| 项 | 值 |
| --- | --- |
| 仓库 | `F:\RustProjects\godot-mcp-pro\code\godot`，分支 `feature/mcp-server-module` |
| **提交锚点（本报告全部结论的复测基准）** | **`427fc79da21314c9123662ea9fa6922119e9b593`**（工作树 `git diff HEAD` = 0 行） |
| plain 引擎 `--version` | `4.8.dev.custom_build.427fc79da` → 与 HEAD 相符 |
| plain 引擎 sha256 | `e125988e36c282de123550c5bb1a5512abea06b239687c549fd73ba394657d01` |
| mono 引擎 `--version` | `4.8.dev.mono.custom_build.4e3de1090` → **≠ HEAD**（见 D-B1） |
| mono 引擎 sha256 | `cd1eb4182a22e987f56101e1c4d4f738d363cc608a6673e8c8a42ac534e336ef` |
| 构建命令 | `modules\mcp_server\scripts\build_local.cmd -Force`（cmd 启动，`tests=yes`，`EXIT_CODE=0`，未抑制 scons 输出） |
| 契约 | `docs/tools_list.renamed.json`，175 条，sha256 `9c70605436a5b559eb973434d9cda6d6a9e0c6bef9ec3318d409137f2ba288f5` |

## 1. verdict

| 分类 | verdict | 一句话依据 |
| --- | --- | --- |
| 机制自洽 | **pass** | 重生成 == 跟踪文件（逐字节，连跑两次同 sha）；171→175 的四桶互斥与 `_meta` 自洽自己跑通 |
| 对等门 | **pass** | 实时 `tools/list` 解析名字，9888=152 / 9889=72，逐条 name/description/inputSchema **零 mismatch**，双向零泄漏 + 跨端点 `-32601` |
| 四个新工具 | **pass** | 四个工具的拒绝/成功/回滚/能力缺失类各给出真实 exit code、sha256 与进程证据 |
| M-5 `sample_stride` | **pass** | 缺省 == 显式 1（逐字节）== 跟踪的改动前基线（逐字节）；stride 10 = 180 观察点回传 18 点；`0`/非整数 `-32602` |
| 顺手性 GDR-25 | **pass** | 6 工具零字符串手术闭环（建工程→写 .csproj→写 .cs→构建→批量校验→独立读回） |
| 工程门 | **pass** | 门①③④⑤⑥ 全绿；doctest 328/328、全量回归 1754/1754、accept_m1 ×2 = 22/22 且 PASS 清单 0 差异 |
| 端口 | **pass** | 9877 全程无监听、未被本审计占用；9888/9889 收尾无监听；无孤儿 `dotnet`/`MSBuild`/`VCSCompiler` |
| **总 verdict** | **pass** | 上一轮 D1 已修复并逐字节复核；遗留项为 1 条环境/构建锚点缺陷（D-B1，不改变四个工具与机制的正确性结论） |

## 2. 机制自洽（任务书 §1.1）

**我自己重生成并逐字节比对**（`gen_renamed_contract.py --out` 两次）：

| 文件 | sha256 |
| --- | --- |
| 跟踪的 `docs/tools_list.renamed.json` | `9c70605436a5b559eb973434d9cda6d6a9e0c6bef9ec3318d409137f2ba288f5` |
| 重生成 #1 | `9c706054…88f5` |
| 重生成 #2 | `9c706054…88f5` |

→ **幂等**（#1==#2）且 **== 跟踪文件**（无手改）。生成器自检 `lint 175/175, unique 175/175`。

**结构化 diff（我自己跑）**：

* 以 `git show d652a43a35:docs/tools_list.renamed.json`（TASK-051，171 条，`_meta` 无 `added_tools`）为基线：
  * 名字并集：171 → 175，**新增恰为 4 条**：`project_build_csharp`、`project_write_text_file`、`project_validate_scripts`、`editor_set_node_script_batch`；它们是契约尾部（`tools[-4:]` == `_meta.added_tools`，有序一致）。
  * **169/171 条移植条目逐字节未变**；变化的 2 条是 `project_validate_script`（TASK-055 D112 改 description）与
    `running_game_get_node_property_samples`（TASK-053 M-5 加 `sample_stride`），**两条都走已声明的 override 通道**，
    并在 `_meta.overrides`（29 条）中逐条留痕（`description/validate_script`、`inputSchema/monitor_properties` 均在表内）。
* 以 `git show c1f3385daf`（TASK-052 首次落地 ADDED，173 条）为基线：**新增 2 条、移植条目改动 0 条**
  → 「新增机制本身不改移植条目」成立。
* `_meta` 增量（171 → HEAD）：只有 `count 171→175`、`generator_version 1.13.0→1.17.0`、`added_count`（新增 4）、
  `added_tools`（新增 4 名）、`overrides`（reason 文本更新）；**`map_sha256` 与 `generated_from_sha256` 未动**。

**四桶互斥 + `--added`（我自己跑，均 PASS）**：

```
ASSERT  171 + 4 = 66 + 105 + 4: PASS (contract = B1/B2 union + B3/B4/B5 union + added)
ASSERT  every one of the 175 contract names is in exactly one of the four buckets: PASS
ASSERT  manifest = contract _meta.added_tools, both directions: PASS (missing=0, foreign=0)
ASSERT  group sizes <= 10: PASS / every added tool appears exactly once: PASS
TOOL-GROUPS-COMPLETENESS CHECK PASS / TOOL-GROUPS-ADDED CHECK PASS
```
`check_tool_groups.py --check-completeness` 与 `--added` 均 `exit 0`。

**ADDED 与两张 override 表分离**：`gen_renamed_contract.py:368 GENERATOR_VERSION`、
`:1237 ADDED_TOOLS`（list，无 `old_name`）、`DESCRIPTION_OVERRIDES`/`SCHEMA_OVERRIDES` 为相互独立的表；
追加发生在 rename+override 之后（`tools[-4:]` 即 `_meta.added_tools`）。

## 3. 对等门（任务书 §1.2）

从**实时 `tools/list` 响应解析**（非文本包含判断），scope 由 `tool-rename-map.json` + `tool-groups-added.json` 派生：

| 端点 | 实时条数 | 派生期望 | 名字集合 | `name`/`description`/`inputSchema` 逐条逐字 |
| --- | --- | --- | --- | --- |
| 9888 editor | **152** | 152 | 完全相等 | **0 mismatch** |
| 9889 game | **72** | 72 | 完全相等 | **0 mismatch** |
| 9888 mono editor | **152** | 152 | 完全相等 | （同一契约视图，`tools/list` 响应的 sha256 与 plain 相同：`7cec3541…9022`） |

* 双向零泄漏：9889 无 editor-only 名（`editor_set_node_script_batch` 等），9888 无 game-only 名
  （`running_game_get_node_property_samples` 等）。
* 跨端点 `-32601`：`running_game_get_node_property_samples` 打 9888 → `-32601`；
  `editor_set_node_script_batch` 打 9889 → `-32601`。

## 4. 四个新工具（任务书 §1.3–§1.6）

### 4.1 `project_build_csharp`

| 类 | 我的请求 | 我的观测 |
| --- | --- | --- |
| ④ **能力缺失** | plain 引擎（无 C#）调用 | `-32000`，message `This engine build has no C# support (no C# script language is registered in this process)`，`data.suggestion` 明确指向 Mono 构建 / `module_mono_enabled=yes`（`e11`、`e13` 两次同结论） |
| ① **从零构建成功** | mono 引擎：`project_set_setting`（工程名）→ `project_write_text_file` 写 `res://AuditB.csproj` → `project_create_script` 写 `res://AuditProgram.cs` → `project_build_csharp` | `exit_code = 0`，`timed_out=false`，`killed=false`，`duration_ms=3651`；产物 `.godot/mono/temp/bin/Debug/AuditB.dll` **6144 B，sha256 `c6886452c5fff44de1eee97c0a048193fe125efadaacc77f7609736e48c40558`** |
| ② **故意错的 `.cs` 不得伪造成 0** | `project_edit_script` 写坏 `AuditProgram.cs` → 构建 | `exit_code = 1`，捕获到编译器原文诊断：`error CS1519: 成员声明中的标记"this"无效`、`error CS1002: 应输入 ;`、`error CS1519`、`error CS1040` |
| ③ **超时真的杀子进程** | 慢 `.csproj`（`Exec ping -n 20`）+ `timeout_ms=2000` | `timed_out=true`、`exit_code=-1`、`killed=true`、`duration_ms=1600`、`effective_timeout_ms=2000`；**收尾清点新出现的 `dotnet`/`MSBuild`/`VCSCompiler` pid = 空** |
| ⑤ **并发/重入不留孤儿** | 收尾前后两次构建 + 超时运行 | 三次清点均为 `[]`；进程全表收尾无 `godot`/`dotnet`/`MSBuild`/`VCSCompiler` 残留 |

失败诊断**回流**到批量校验：构建失败后 `project_validate_scripts` 对 `res://AuditProgram.cs` 给出
`category=invalid`、`valid=false`、`error_text` 为编译器原文（含 `CS1519`/`CS1002`）。

### 4.2 `project_write_text_file`

* 成功写 `.csproj` 后读回 `sha256` 与盘上一致；**独立读者**（`project_search_file_contents`，不是写者）读到
  `res://audit-readback.cfg` 的 `marker=audit-added-mono`（1 命中）。
* **四类拒绝各一条**（均 `-32602` + 指向正确工具的建议）：
  | 目标 | message 摘 | suggestion |
  | --- | --- | --- |
  | `res://project.godot` | 「the project's own settings file, which this tool does not write」 | 指向 `project_set_setting` |
  | `res://scenes/main.tscn` | 「which has a dedicated tool」 | 指向 `project_create_scene_file` / `editor_save_scene` |
  | `res://scripts/valid.gd` | 「which has a dedicated tool」 | 指向 `project_create_script` / `project_edit_script` |
  | `res://../escape.txt` | 「must not walk upwards with '..'」 | 指向「只写工程内」规则 |
  另外 `.cs` 目标也走同一条家族拒绝并指向 `project_create_script`（`e10`/`e12`）。
* `overwrite:false` 命中已存在 → **`-32000`**，message 点名 `already exists and 'overwrite' is false`，
  `data.suggestion` 逐字含 `"overwrite": true`；**文件字节未变**（前/后 sha256 均 `2656b6e1a84481123147da0fa731e3bcf5d8ec130e24815cbc6d2fe83ae55889`）。
* **无删除路径**：运行腿 —— `remove=true`、`delete=true`（仅删除参数）均 `-32602 Unknown parameter`，
  `data.suggestion` 列出唯一接受的三个参数（`content, overwrite, path`），且文件 sha 不变；
  代码腿 —— `project_text_write.cpp` 全文**不含** `remove`/`delete`/`unlink`/`DirAccess::remove` 任何 token。

### 4.3 `project_validate_scripts`

见 §5（本轮必查①②）与 §6.4。批量/单数、计数器求和、`-32602`（`paths` 越界）、`-32001`（文件不存在，
建议指向 `project_list_scripts`/`project_create_script`）均自跑验证。

### 4.4 `editor_set_node_script_batch`

* **全成功**：`status=ok`、`count=2`、`attached` 两条 `attached=true` 且 `script_path` == 请求值、`skipped=0`。
* **全回滚（中间失败）**：3 个节点、第 3 个不存在 → `-32001`，`error.data.batch` =
  `{status:"rolled_back", rolled_back:true, on_error:"all_or_nothing", count:0, attached:[], errors:[{index:2, node_path:"NoSuchNode", reason:"... not in the edited scene"}]}`；
  **树状态未变**：拒绝后保存并读回的场景文件 sha256 == 成功批次后的场景 sha256
  （均 `f1c8048309b7f37faca9b8ac28eb04d98da76b1765135acdeb1e76abaca0e248`）。
* **`keep_existing:true` 跳过并计入 `skipped[]`**：`count=0`、`attached=[]`、`skipped` 两条，
  每条 `previous_script_path == res://scripts/valid.gd`、`reason` 含 `keep_existing`；
  再保存后场景 sha256 仍等于成功批次后的 sha256（**未覆盖已挂脚本**）。
* 第三次用**独立读者** `project_read_scene_file_content` 读盘上字节：仍含 `res://scripts/valid.gd`，
  **不含** `res://scripts/other.gd`。
* 参数面：`keep_existing:"yes"` → `-32602`（要求 boolean）。

## 5. 本轮必查① 与 ②（逐字检查）

### ① `language_unavailable` 不得出现 `"valid": false`

plain 引擎对 `valid.gd / broken.gd / legit.cs / note.gdshader / abstract.gd` 的批量响应（`e03`，与重复调用的
`e03b` **sha256 相同**，`72e37ba290192b…`）：

| path | category | `valid` 键 | `valid` | `reason` | language |
| --- | --- | --- | --- | --- | --- |
| `res://scripts/valid.gd` | `ok` | 有 | `true` | — | gd |
| `res://scripts/broken.gd` | `invalid` | 有 | `false` | — | gd |
| `res://scripts/legit.cs` | **`language_unavailable`** | **有** | **`null`** | **有** | cs |
| `res://note.gdshader` | **`language_unavailable`** | **有** | **`null`** | **有** | gdshader |
| `res://scripts/abstract.gd` | `ok` | 有 | `true` | — | gd |

* **逐字响应字节扫描**：整段响应正文里 `"valid":false` 字面量**只出现 1 次**，且它落在
  `res://scripts/broken.gd`（`category=invalid`）这一条内；**没有任何 `language_unavailable` 条目带 `"valid":false`**。
* `language_unavailable` 条目同时带 `category`、`reason`（引用 `get_language_for_extension`）、`suggestion`。
* mono 引擎同样成立：`note.gdshader` → `category=language_unavailable`、`"valid":null`、带 `reason`。
* 代码腿：`project_validate_scripts.cpp:154-176` —— `unverifiable` / `not_compiled` / `language_unavailable`
  三类统一 `entry["valid"] = Variant()`（JSON `null`），`false` 只在 `ok`/`invalid` 两个真结论上发布。
* doctest 腿：`tests/test_mcp_server.h:25863-25890` 用 `cs["valid"].get_type() == Variant::NIL` 钉住
  （并注明 `(bool)cs["valid"]` 不够，正是缺陷当年的藏身处）。

### ② 单数与批量对同一文件的结论一致

| path | 单数 `project_validate_script` | 批量 `project_validate_scripts` | 一致 |
| --- | --- | --- | --- |
| `res://scripts/valid.gd` | `code=0`，`valid=true` | `ok / valid=true` | ✅ |
| `res://scripts/broken.gd` | `code=0`，`valid=false` | `invalid / valid=false` | ✅ |
| `res://scripts/legit.cs` | `code=-32000` + 建议指向 Mono 构建 | `language_unavailable / valid=null` | ✅ |
| `res://note.gdshader` | `code=-32000` + 建议（无该后端） | `language_unavailable / valid=null` | ✅ |
| `res://scripts/abstract.gd` | `code=0`，`valid=true` | `ok / valid=true` | ✅ |

规则：`ok↔valid:true`、`invalid↔valid:false`、其余类别 ↔ 单数 `-32000` 拒绝（绝不互相给出相反真结论）。
5/5 一致，**0 分歧**。mono 端对 `.cs`：未构建 → `not_compiled`（`valid:null`），构建失败后 → `invalid`。

## 6. 其余必查与门

### 6.1 ③ `docs/tool-groups-added.json` 生成器版本字段已同步

| 出处 | 值 |
| --- | --- |
| `gen_renamed_contract.py:368 GENERATOR_VERSION` | `1.17.0` |
| `docs/tools_list.renamed.json` `_meta.generator_version` | `1.17.0` |
| `docs/tool-groups-added.json` `source.entries` | `… ADDED_TOOLS (generator v1.17.0, TASK-052 section 1 + TASK-053 section 2.1/2.2)` |

三处相等（`ALL_THREE_EQUAL = True`）。清单并集 == `_meta.added_tools`（双向），`total=4`、`counts={added_tools:4, groups:4}`。
**注意**：该版本字段是 `source.entries` 里的**自由文本**，`check_tool_groups.py` **不做机器校验**（见 R-B2）。

### 6.2 ④ `project_build_csharp` 的 `command` 分隔符一致

实测（mono，`n02`）：

```
command   = C:\Program Files\dotnet\dotnet.exe build C:/Users/wyl/AppData/Local/Temp/audit-added/rt/proj/AuditB.csproj -c Debug
commands  = [同一条]
```

* 本机 PATH 第一条 dotnet 目录是 `C:\Program Files\dotnet\`（**带尾反斜杠**），正是 `D3` 的触发形态。
* 输出中**没有** `\/`、没有 `\\`、没有 `//`；`dotnet.exe` 只出现 1 次；`\dotnet.exe` 前恰一个分隔符。
* 代码腿：`csharp_executable_path()`（`project_csharp_build.cpp:354+`）把目录归一化到平台分隔符、
  去掉尾部重复分隔符、只插一个；`path_join` 只认尾部 `/`（`core/string/ustring.cpp:5061` 已复核）。
* argv 分隔符一致：`csharp_build_command_line()` 以**单个空格**拼接 (`.cpp:488-493`)，`commands[]` 元素与
  `command` 逐字相同。doctest：`test_mcp_server.h:25435-25460`（Windows/POSIX/UNC/空串/纯空白 6 例）。

### 6.3 ⑤ 上一轮「未跑的那些电池」这次是否跑了

我**自己跑**了 `scripts/mcp056_regression_battery.ps1`（15 步，串行，无并发 scons）：

| # | 步骤 | exit | 结果 |
| --- | --- | --- | --- |
| 1 | `accept_m1.ps1` run1 | 0 | 22/22 cases passed |
| 2 | `accept_m1.ps1` run2 | 0 | 22/22 cases passed（两次 PASS 清单 **differing_lines=0**） |
| 3 | `mcp041_gates.ps1` | 0 | `STEP regress_mcp040_racing EXIT 0 (48s)` |
| 4 | `mcp042_gates.ps1` | 0 | 同上 EXIT 0 |
| 5 | `mcp043_gates.ps1` | 0 | 同上 EXIT 0 |
| 6 | `mcp010_b2_observation_evidence.ps1` | 0 | 29/29 |
| 7 | `mcp019_b4_evidence.ps1` | 0 | 通过（含 9877 guard PASS） |
| 8 | `mcp027_object_shape_and_paths_evidence.ps1` | 0 | 60/60 |
| 9 | `mcp044_capture_evidence.ps1` | 0 | 40/40（含 9877 guard） |
| 10 | `mcp045_pixel_compare_cost.ps1` | 0 | 15/15 |
| 11 | `mcp046_capture_encode_cost.ps1` | 0 | 23/23 |
| 12 | `mcp050_parameter_guidance_evidence.ps1` | 0 | 9877 guard pass=True |
| 13 | `mcp051_b_tier_evidence.ps1` | 0 | 9877 guard pass=True |
| 14 | `mcp052_added_tools_evidence.ps1` | **1** | **52/53**，唯一 FAIL = `engines_match_head`（见 D-B1） |
| 15 | `mcp053_added_tools_evidence.ps1` | **1** | **72/73**，唯一 FAIL = `engines_match_head`（见 D-B1） |

→ **15/15 步都跑了**（不是「未跑」）。**13 步全绿**；第 14/15 步各有一条 `engines_match_head` FAIL，
两次 FLAG 内容完全相同：`plain --version='4.8.dev.custom_build.427fc79da' mono --version='4.8.dev.mono.custom_build.4e3de1090' git HEAD='427fc79da'`。
即：**上一轮 15/15 exit 0 的说法在本树上不可复现**，差的不是行为，而是 mono 二进制的版本锚点。

### 6.4 M-5 `sample_stride`（任务书 §1.7）

| 检查 | 我的观测 |
| --- | --- |
| 缺省 vs 显式 1 | 两次响应**逐字节相同**（sha256 均 `eef36e62799a54128c66081596c8827833095d023ae45c54275a890f75b2b67a`） |
| 缺省是否追加新字段 | **否**：`sample_stride` / `observed_count` 两个键都不出现，`samples` 5 点 |
| 与**改动前基线**逐字节 | 与跟踪基线 `docs/reports/evidence/task053/m5-baseline/baseline.json` 的 `response_sha256` **完全相同**（该基线在 `git_head_at_capture=c4823798a`、引擎 sha256 `bf16508d…` 上采集） |
| 显式步长 | `frame_count=180` 无步长 → 180 点（6147 B）；`sample_stride=10` → **18 点**、`observed_count=180`、`sample_stride=10`、`frame` 序列 `0,10,20,…,170`，线上字节 781 < 6147 |
| `0` | `-32602`，message 含 `at least 1` |
| 非整数（`"every"` / `1.5`） | `-32602`（`must be an integer` / 类型拒绝） |

### 6.5 顺手性 GDR-25（任务书 §1.8）

**一条跨 6 工具的零字符串手术链**（全部本人实跑，均为真实 HTTP 响应）：

```
project_set_setting(application/config/name)            -> value="AuditAddedB", saved=true
  -> project_write_text_file(res://AuditB.csproj)       -> created=true, sha256=…（与盘上一致）
  -> project_create_script(res://AuditProgram.cs)       -> 成功
  -> project_build_csharp(configuration=Debug)          -> exit_code=0, AuditB.dll sha256=c6886452…
  -> project_validate_scripts(paths=[…])                -> invalid + 编译器原文（构建失败后）
  -> project_search_file_contents(pattern=…)            -> 1 命中，读回写者写入的字节
```

* 调用方**零字符串处理**：我自己的调用脚本（`probe.ps1`）里对工具返回值做 `Substring`/`Split`/`Replace`/
  `-replace`/`Trim` 的行数 = **0**；返回值（路径、sha256、`command`、`results[]`）直接喂回下一个调用。
* 误差收敛点：`.csproj` 由 `project_write_text_file` 写、`.cs` 被正确地推给 `project_create_script`
  （写者主动拒绝并点名该工具），构建工具自动发现工程文件，全程无人工拼路径。

### 6.6 六道门（任务书 §1.9，全部自跑）

| 门 | 命令 | 结果 |
| --- | --- | --- |
| ① 契约逐字（**4 组** ≥3） | `check_contract_subset.ps1`（默认 `project_read_template`、`-Group project_validate_scripts`、`-Group project_csharp_build`、`-Group editor_set_node_script_batch`） | 4/4 组 `editor_9888_contract_subset` + `game_9889_contract_subset` + `guard_user_port_9877` PASS，`3/3 checks passed`，`contract=175` |
| ② 证据脚本（≥3 个） | 见 §6.3 的 15 步 | 13 步全绿、2 步各 1 条 D-B1 |
| ③ doctest | `--headless --test --test-case=[MCPServer]*` | `328/328 passed`，`23541/23541 assertions`，`Status: SUCCESS!` |
| ④ 全量回归 | `--headless --test` | `1754/1754 passed`，`447764/447764 assertions`，`Status: SUCCESS!` |
| ⑤ accept_m1 ×2 | `accept_m1.ps1` 两次 | 两次 `22/22`，PASS 清单 `differing_lines=0` |
| ⑥ 三段式 narrowing | `check_narrowing_points.py` + `--coverage` + `mcp031_gate6_coverage_probes.ps1` | 三步 exit 0，探针 `101/101 checks passed`（含 `B1b_restored_scanned_75` / `byte_identical` / `worktree_clean_of_probes`） |

端口纪律：9877 审计前后均**无监听**（pid=-1），`mcp_port_guard` 判定
`pass=True classification=environment_fact_no_listener_before_or_after`，本次启动的进程 pid
`[84968, 87812]` / `[48368]`，请求端口集合 `[0,9888,9889]`，**从未请求 9877**。
收尾：9888/9889 无监听、无 `godot`/`dotnet`/`MSBuild`/`VCSCompiler` 进程、**无任何 git 写操作**（未 commit/push）。

## 7. defects

### D-B1（中）— mono 引擎不是 HEAD，两条仓库自带检查稳定红

* 事实：`bin\godot.windows.editor.x86_64.mono.console.exe` 报告
  `4.8.dev.mono.custom_build.4e3de1090`，而 HEAD = `427fc79da`；`4e3de1090` 在 `75adcdcce8`（D1/D2/D3 修复提交）
  **之前**。文件 mtime `2026/09/25 00:06`，早于 `75adcdcce8` 的提交时间 `00:45:30`。
* 复现：`mcp052_added_tools_evidence.ps1` → 52/53（FAIL `engines_match_head`）；
  `mcp053_added_tools_evidence.ps1` → 72/73（同一 FAIL）。两条在本树上**稳定失败**，与代码行为无关。
* **反证（对结论有利）**：该 mono 二进制在运行腿上是**修复后**的行为——
  `project_build_csharp` 的 `command` 输出单分隔符（D3 生效，未修复时应为 `C:\Program Files\dotnet\/dotnet.exe`，
  依 `core/string/ustring.cpp:5061`）；`note.gdshader` 的 `language_unavailable` 给出 `"valid":null`（D1 生效）。
  故它是在**脏工作树**（已含 D1/D3 改动、未提交）上构建的。
* 影响：不改变四个新工具与机制的正确性结论（plain 引擎 = HEAD，D1 已在 plain 上逐字节复核，mono 端
  在 `.gdshader` 上复核）；但**任何「mono 引擎 == HEAD」的声明不可复现**，且上一轮 mono 相位证据的构建锚点
  不是提交哈希。本轮 verdict 仍为 **pass**，若决策者把「验收电池不得有红步」作为硬门槛，则须先关闭 D-B1。
* 建议修复动作：用 `module_mono_enabled=yes tests=yes` 在 HEAD 提交上重建 mono 引擎，再跑 `mcp052`/`mcp053`
  取 53/53 与 73/73，并在证据里记录 mono 引擎 sha256。

## 8. unconfirmed（我未能证实的部分）

1. **`unverifiable` 的运行实例**：本轮 4 次批量校验（plain 混合、plain 单文件、mono 单文件、mono 全扫描）
   都没有产出 `category=unverifiable` 的条目——我未能构造出「引擎无法把文件当 `Script` 载入」的输入。
   该类别只有**代码腿**（`project_validate_scripts.cpp:154-176`，与另两类同一分支）与 **doctest 腿**
   （`test_mcp_server.h`）支撑，运行腿形状未由我复现。
2. **M-5「改动前逐字节」的基线来源**：我的缺省响应与跟踪的 `baseline.json` 逐字节相同，但我没有亲眼见证
   那次基线采集（该文件声明采集于引擎 `bf16508d…`/`git_head_at_capture=c4823798a`）。独立佐证是
   「缺省 == 显式 1」逐字节相同 + 缺省响应不含两个新键 + 代码腿只看 `sample_stride > 1` 才追加。
3. **POSIX 分隔符分支**：本机为 Windows，`csharp_executable_path(..., p_windows=false)` 只有 doctest 覆盖，
   没有运行腿证据。
4. **在 HEAD 上构建的 mono 引擎**：见 D-B1，本轮所有 mono 结论都来自 `4e3de1090` 版本串的二进制。

## 9. risks

* **R-B2（低-中）**：`tool-groups-added.json` 的生成器版本是自由文本，`check_tool_groups.py` 不校验它。
  D2 这一类漂移（清单写 1.16.0 而生成器是 1.17.0）**没有机器护栏**，下次升版本仍可能静默落后。
  建议把版本号纳入 `--added` 的断言（或从生成器注入）。
* **R-B3（低）**：本轮 15 步电池里 13 步会把**跟踪的**证据文件覆盖重写（`docs/reports/evidence/task0xx/…`），
  加上 `mcp051` 会新建 `task051/red/e20_child_status.json`。跑完必须 `git checkout -- .` 还原，
  否则「证据 = 历史记录」的可信度被下一次运行覆盖（我已还原，见 §10）。
* **R-B4（低）**：`project_build_csharp` 在 plain 构建下只能给出 `-32000` 能力拒绝，因此
  「从零构建成功 / 坏 `.cs` / 超时」三类**只能**在 mono 引擎上验收；mono 引擎的可用性因此是这条工具
  验收链的单点依赖（与 D-B1 叠加）。

## 10. 临时实验的逐字节还原（留证）

* 运行前工作树脏项：仅 4 个既有未跟踪项（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`）。
* 运行中被改写的**跟踪**文件（共 22 个 task053 证据文件 + 后续电池/门脚本覆盖的 task050/task051/task056 证据）
  已由 `git checkout -- .` **逐字节还原**：还原后 `git diff --stat HEAD` = **0 行**，未跟踪项回到同样的 4 个。
* 运行中新建的未跟踪产物 `modules/mcp_server/docs/reports/evidence/task051/red/e20_child_status.json`
  已删除（还原为运行前状态）。
* 我在 `%TEMP%\audit-added\` 下的私有证据（原始请求/响应字节、日志、我的探针脚本）全部保留在
  `C:\Users\wyl\AppData\Local\Temp\audit-added\`（`rt\evidence\` 为原始响应，`analysis.json` 为我的 62 项判定，
  `probe.log` / `probe_mono.log` / `probe_mono2.log` 为进程级证据）。
* 我的判定脚本自跑结果：**62 / 62 checks pass，failed = 0**（含 §5、§6.4、§6.5 全部条目）。

## 11. next_step_recommendation

1. **关闭 D-B1**：在 HEAD（`427fc79da`）上以 `module_mono_enabled=yes tests=yes` 重建 mono 引擎，记录其
   sha256，重跑 `mcp052`/`mcp053` 应得 53/53 与 73/73；把 mono 引擎 sha256 写进证据，使 mono 相位可复现。
2. **关闭 R-B2**（可选、低成本）：把生成器版本号做成 `check_tool_groups.py --added` 的一条断言。
3. 若决策者要求 `unverifiable` 的运行腿形状也被钉住：构造一个「扩展名有后端但引擎仍无法当 Script 载入」的
   输入（例如同名资源冲突/损坏的 `.gd`），补一条活体证据。
4. 本轮对象（四个新增工具 + 契约扩张机制 + D1 修复）**可判 pass**，可进入下一阶段；
   D-B1 属于构建/环境锚点，不阻塞功能验收。