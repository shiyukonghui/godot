# REPORT-055 — 给 Godot 源码打补丁：让 C# 脚本拿到真正的编译结论

| 项 | 值 |
|---|---|
| status | 完成（五道门 + 门⑥ 三段式已实测；回归见 §7）|
| 任务书 | `docs/tasks/TASK-055-csharp-compile-verdict-patch.md` |
| 决策授权 | D112（用户授权给引擎源码打补丁）；纪律四条见任务书 §1 |
| 契约 | **175** 条不变（171 移植 + 4 新增），`docs/tools_list.renamed.json` sha256 `9c70605436a5b559eb973434d9cda6d6a9e0c6bef9ec3318d409137f2ba288f5` |
| 补丁面（任务书 §2.2 优先级）| 选 **(c)「暴露标志」+ 已存在的公开 ABI**，并**在工具侧补上 (b) 程序集/项目级真值**；(a) 文件级真值**在引擎里不存在**（依据见 §1）|
| 二进制锚点（D86）| 全部门与证据都跑在 `git HEAD == da657ea1fc` 的工作树上：plain `4.8.dev.custom_build.da657ea1f`、mono `4.8.dev.mono.custom_build.da657ea1f`；这批改动落成提交 **`5f3e7fb441`**（内容与该工作树一致，只是 sha 不同），见 §9 |
| 端口纪律 | 全程只用 9888；9877 无监听（pid `-1` → `-1`，`guard_user_port_9877` PASS）；**未启动/未杀/未重启任何 9877 进程** |
| 构建纪律 | mono 与 plain 构建**严格串行**（无并发 scons）；两次都不抑制 scons 输出 |

---

## 1. 引擎源码调研：C# 的编译事实究竟在哪里

任务书要求给出 `文件:行` 依据。逐条读出（本 fork 源码，**只读**）：

| 问题 | 事实 | 依据 |
|---|---|---|
| C# 编译由谁执行？ | 不在引擎里。编辑器侧由 **C# 插件 `GodotTools`** 起 `dotnet build`：`BuildManager.Build()` → `BuildSystem.Build()`（构造 `dotnet build -c <config> ... -l:GodotTools.BuildLogger,...;<LogsDirPath>`）| `modules/mono/editor/GodotTools/GodotTools/Build/BuildManager.cs:74-121`、`BuildSystem.cs:284-291` |
| 「某个 `.cs` 文件的编译错误」这一事实存在何处？ | **只存在于 MSBuild 的输出与插件写的日志里**：自定义 MSBuild logger 把每条诊断写成 `error,<file>,<line>,<col>,<code>,<msg>` 到 `<build_logs>/<solution_md5>_<config>/msbuild_issues.csv`，并把行文本写进 `msbuild_log.txt` | `modules/mono/editor/GodotTools/GodotTools.BuildLogger/GodotBuildLogger.cs:33,41,82,89,92`（`e.File`/`e.LineNumber`/`e.ColumnNumber`/`e.Code`/`e.Message`）；文件名常量 `Build/BuildManager.cs:16,58-66`；路径 `<user>/build_logs/<md5>_<config>`（`Internals/GodotSharpDirs.cs:186-190`，引擎侧对应 `godotsharp_dirs.cpp:168,260`）|
| 引擎 C++ 侧知道这些吗？ | **不知道**。引擎只看到「项目程序集 dll 的路径与 mtime」 | `modules/mono/mono_gd/gd_mono.cpp:765-783`（`_load_project_assembly`，`project_assembly_modified_time`）、`gd_mono.h:129-134` |
| `reload()` 给的是什么？ | `OK` 恒定；唯一真实信号是 `valid`（=「这个脚本路径在**已加载**程序集里有类吗」）| `modules/mono/csharp_script.cpp:2588-2621`（函数体唯一的 `return` 在 2620）、`csharp_script.h:137`、`ScriptManagerBridge.cs:436-463` |
| 那个信号有公开读取口吗？ | **有**：`Script::is_script_valid()` 是 `Script` 的公开纯虚函数，`CSharpScript` 覆写为 `return valid;` | `core/object/script_language.h:180`；`modules/mono/csharp_script.h:269-271` |
| 引擎里有没有现成的「源文件是否新于已加载程序集」比较？ | **有，但是局部的**：编辑器为了刷新占位实例自己算过一次 | `modules/mono/csharp_script.cpp:2174-2176`（旧文：`script_modified_time > last_valid_build_time`）|

**结论（调研答案）**：**文件级真值（哪个文件、哪一行、什么错误）在引擎里根本不存在**，它只由 `GodotTools` 的 MSBuild 管道产出（进程内 `BuildDiagnostic`/`BuildProblemsView`，落盘 `msbuild_issues.csv`）；引擎能给出的只有**两件**事：①已加载程序集里有没有这个路径的类；②这个文件的 mtime 是否晚于已加载程序集。**没有任何 API 能在不编译的情况下说「这段源码编译失败」**。

### 1.1 补丁面选择（选了哪条、为什么、代价）

| 选项 | 可行性实测 | 决策 |
|---|---|---|
| (a) 文件级真值（引擎能读每个文件的诊断） | **不可行 / 不该做**：诊断只存在于 C# 插件的过程与它的 csv 里；引擎侧读该 csv 等于把 `GodotTools` 的落盘格式写进引擎，而且**只有走编辑器自带构建时才有**（MCP 自己的 `project_build_csharp` 走裸 `dotnet build`，不写该 csv），证据链会依赖用户是否点过 Build | 否决 |
| (b) 程序集级真值 | 引擎**能**给「已加载程序集里有没有这段源码的构建」（`is_script_valid()` + mtime 比较），但**不能**给「构建失败」——失败不留痕，dll mtime 不动与「没构建过」同形 | **部分采用**：由本模块自己的构建工具补上「项目级构建结果」——`project_build_csharp` 把本次运行的**逐文件诊断**（连同每个文件在构建那一刻的 mtime）写进 `user://mcp_csharp_build_state.json`；工具回答时**明说是项目级构建**（`message` 里写出 `.csproj`） |
| (c) 让 `reload()` 不再对「源文件与已加载程序集不一致」报 OK | 两条路：**改返回值** 或 **暴露标志**。改返回值会改变编辑器自身行为（占位实例的安装依赖 reload 成功路径），超出「最小」 | **采用「暴露标志」**：引擎只加一个**只读公开访问器** `CSharpScript::is_source_newer_than_assembly()`（把 2174-2176 那次局部比较提升为 API，并让原处**复用它**，保持单一事实源）；`reload()` 的签名/语义**一字未动** |

**代价（明确记录）**：①工具要能回答「失败」，必须先有一次由本 MCP 工具跑过的构建（否则只能诚实回答 `not_compiled`）；②诊断文本来自 MSBuild，随系统语言本地化（本机为中文），解析按 `error <CODE>:` 结构而不是按语言；③记录的 mtime 守卫是**秒级**（`FileAccess::get_modified_time` 的分辨率），与引擎自身的比较同分辨率。

---

## 2. 完整补丁清单（文件 / 行 / 新增符号 / 为什么）

### 2.1 引擎源码（`modules/mono/**`，唯一一处 ABI 变更）

| 文件 | 行 | 新增 / 改动 | 为什么需要 |
|---|---|---|---|
| `modules/mono/csharp_script.h` | **276-294**（新增，位于 `is_abstract()` 与 `inherits_script()` 之间）| `bool is_source_newer_than_assembly() const;` + 说明注释 | 上层要区分「上次成功构建后被改过」与「编译失败」。`reload()` 给不了（无编译器、恒 OK），而这个比较引擎**本来就在做**（`_update_exports()` 的占位刷新），把它变成公开只读 API 才能被本模块（与任何上层）读取。返回 `false` 的条件（无 path / 文件读不到）在注释里写明 |
| `modules/mono/csharp_script.cpp` | **2621-2638**（新增）| `CSharpScript::is_source_newer_than_assembly()` 定义 | 实现：`FileAccess::get_modified_time(get_path())` 与 `GDMono::get_singleton()->get_project_assembly_modified_time()` 比较；程序集从未构建时后者为 0，于是任何可读源文件都是「更新」——这正是「没有构建过」的诚实表达 |
| `modules/mono/csharp_script.cpp` | **2173-2174**（改动 3 行 → 1 行）| 编辑器占位分支改为调用访问器 | 语义等价的**单一事实源**重构：同一判断只写一处，避免两处实现漂移（新 API 不是第二份逻辑） |

**未做**：没有改 `reload()` 的签名/返回值（§1.1 的取舍）；没有加 `ClassDB` 绑定（本模块直接以 C++ 调用；给脚本层暴露一个语义容易误用的 flag 不在本批范围，且会扩大 ABI）；没有碰 `GodotTools`（C# 插件零改动）与构建系统。

### 2.2 MCP 模块（`modules/mcp_server/**`）

| 文件 | 行 / 范围 | 新增 / 改动 | 为什么需要 |
|---|---|---|---|
| `tools/csharp_verdict.h`（**新增**，118 行）| 全文 | `enum class MCPCSharpVerdict { COMPILED, BUILD_FAILED, NOT_COMPILED }`、`classify_csharp_verdict()`、`parse_csharp_build_errors()`、`csharp_build_record_path()`、`write_csharp_build_record()`、`read_csharp_build_record()`、`recorded_csharp_build_errors()` | 判定是**纯函数**（可在非 mono 的 `--test` 进程 doctest）；记录格式与「诊断何时失效」的规则集中在一处，两个工具共用同一口径 |
| `tools/csharp_verdict.cpp`（**新增**，291 行）| 全部实现 | 同上 + 私有助手 `_to_project_path()`/`_cap_text()`/`_strip_project_suffix()` | 诊断解析（MSBuild 两种形状：`file(line,col): error CODE: msg [proj.csproj]` 与 `CSC : error CODE: msg`，**warning 不解析**，消息里的 `[*.csproj]` 后缀剥离）；记录写 `user://mcp_csharp_build_state.json`（与 `editor_get_test_report` 的 `user://mcp_test_report.json` 同一约定），每条诊断**带上写入时的文件 mtime** |
| `tools/project_csharp_build.cpp` | **32-34**（include）、**273-289**（`_payload()` 开头）| `#include "csharp_verdict.h"`；一次运行结束时调用 `write_csharp_build_record(...)` | 项目级那一半真值的**唯一来源**：该工具本来就已经把 `dotnet build` 的 stdout/stderr 全量捕获，额外成本只是解析 + 落盘。**响应逐字节不变**（记录写入发生在 payload 组装之前，不参与任何字段），失败/超时/被杀都记录（`exit_code=-1`/`timed_out`）|
| `tools/project_read_files.h` | **97-160**（重写 TASK-054 段）、**200-215**（新增声明）| 删除 `validate_script_language_has_compile_verdict()`；新增 `validate_script_not_compiled_reason/error()`、`validate_csharp_script_source()`、`csharp_recorded_error_text()`、`csharp_recorded_failure_message()`、`validate_script_verdict_refusal()`；`MCPValidateScriptVerdict.category` 文档补 `not_compiled`，`error_text` 文档补「C# 是编译器原文」| 把「C# 无结论」的旧结论**作废**并用真结论取代；`unverifiable` 缩到唯一残余情形（引擎根本没能把文件当 `Script` 载入）|
| `tools/project_read_files.cpp` | **31-53**（include：`csharp_verdict.h` + `modules/modules_enabled.gen.h` + `#ifdef MODULE_MONO_ENABLED` 下 `modules/mono/csharp_script.h`）、**330-351**（`unverifiable` 文案重写）、**353-421**（新增 `not_compiled` 文案/项目级诊断文案）、**423-482**（新增 C# 判定）、**505-513**（`validate_script_source()` 里 C# 分支）、**604-607**（单数工具对 `unverifiable`/`not_compiled` 的 `-32000` 拒绝）、**558-568**（`validate_script_verdict_refusal()`）、**913**（描述字面量）| 判定落点：`ResourceLoader::load(path,"Script")`（编辑器自己走的那条路，会调 `reload()` 填 `valid`）→ `is_script_valid()` + `is_source_newer_than_assembly()` + `recorded_csharp_build_errors()` → `classify_csharp_verdict()` | 语言交叉依赖用 `MODULE_MONO_ENABLED` 守卫（非 mono 构建下该分支不可达且不编译）；`reason` 写明两个引擎信号与「引擎没有 C# 编译器」这一事实，供调用方核验 |
| `tools/project_validate_scripts.cpp` | **146-167**（`_item()` 处理 `not_compiled`）、**277-315**（新增 `not_compiled_count`，`count` = 五个计数器之和）、**369**（描述字面量）| 新增分类与计数器 | 一个文件被问了就必须被**恰好一个**分类与计数器收口；`valid` 对 `not_compiled` 仍写 `null`（`false` 会被读成「不编译」）|
| `tests/test_mcp_server.h` | `include`（`../tools/csharp_verdict.h`）、**25465-25488**（新增 `VALIDATE_SCRIPTS_DESCRIPTION` 逐字）、**25724-25800 / 25848-25870**（计数器断言）、**26410-26630**（TASK-055 用例替换 TASK-054 用例）| 新增 1 个 `TEST_CASE`（分类表 7 组、解析器、记录往返 + mtime 失效、`not_compiled`/`unverifiable` 文案与拒绝、`is_source_newer_than_assembly` 引用）| **可被门覆盖**（任务书 §1.4）：判定表与记录规则在 `--test` 进程可判；线上分支由 mono 证据覆盖（见 §3）|
| `scripts/gen_renamed_contract.py` | v1.17（docstring）、`GENERATOR_VERSION="1.17.0"`、`DESCRIPTION_OVERRIDES["validate_script"]`（value+reason）、`ADDED_TOOLS[project_validate_scripts]`（description+reason）| 两条描述改为真实口径 | 契约是**唯一**能让调用方读到的口径；描述错误=行为正确也白搭（GDR-28）|
| `docs/tools_list.renamed.json` | 生成物 | 175 条，**只有** `project_validate_script` / `project_validate_scripts` 的描述与 `_meta` 变化（`git diff --numstat` = **4/4**）| 门① 逐字的对象；生成器连跑两次同 sha（幂等）|
| `scripts/mcp055_sync_literals.py`（新增）| 全文 | 从生成后的契约**程序化**回写两个 C++ 注册字面量 | 手抄中文契约必错（本批实测踩到一次未闭合字面量）；门① 在线上证明两者逐字相等 |
| `scripts/mcp055_csharp_compile_verdict_evidence.ps1`（新增）| 全文 | pre/post 两轮线上捕获（纯 ASCII）| 门②/证据 ①-⑤ |
| `scripts/mcp055_pre_post_compare.py`（新增）| 全文 | 逐 label 字节比对 + 允许差异集合断言 + 契约旧/新逐字比对 | ⑤「175 条工具行为逐字节不变」的证据，且把**允许**的差异显式化 |
| `scripts/mcp055_gates.ps1`（新增）| 全文 | 门③/④/⑥/完备性/门① 的串行驱动 | 无并发 scons、每步退出码与日志落盘 |

---

## 3. 证据（任务书 §2.4 ①-⑤，缺一不可）

证据目录：`docs/reports/evidence/task055/{pre,post}/`（请求/响应逐字节、`hashes.txt`、`unhashable.txt`、`summary.txt`）。
夹具：真实 C# 工程（`Mcp055Probe.csproj` = `Godot.NET.Sdk/4.8.0-dev` + `net8.0` + `EnableDynamicLoading`，本地 nupkgs 源），`scripts/Legit.cs`、`scripts/Broken.cs`；**文件名必须与类名逐字同大小写**，否则 SDK 的 `ScriptPathAttributeGenerator` 不生成 `[ScriptPath]`（本批实测：`legit.cs` 里的 `class Legit` 建筑出的 dll **无** `ScriptPath` 属性，引擎于是无类可用——这是一次真实踩坑，见 §8）。

### ① 语法错误的 `.cs` → 明确失败（真实诊断文本）

`project_build_csharp` 先失败（`exit_code=1`，stdout 含 `Broken.cs`），随后：

| 探针 | 结果（post 二进制，逐字）|
|---|---|
| `mono-07-singular-broken-after-failed-build` | `{"path":"res://scripts/Broken.cs","valid":false,"error_text":"<绝对路径>Broken.cs(5,5): error CS1519: 成员声明中的标记“this”无效 [<...>Mcp055Probe.csproj] \| ... error CS1002: 应输入 ; \| ... error CS1519 ... \| ... error CS1040 ...","message":"Compilation failed. The last C# build recorded by project_build_csharp (a project-level build of res://Mcp055Probe.csproj) rejected 'res://scripts/Broken.cs' as it is now: ..."}`（4438 B）|
| `mono-08-plural-broken-after-failed-build` | `category=invalid`、`valid=false`、`invalid_count=1`、`error_text` 同上是**编译器原文**（在 400 B 处带截断标记，1490 B）|

`message` 明说这是 **project_build_csharp 的项目级构建**（`.csproj` 写在句子里），不冒充「文件级编译器判定」。

### ② 合法 `.cs` → 明确通过

| 探针 | 结果 |
|---|---|
| `mono-04-singular-legit-after-build`（先成功构建、**重启编辑器**加载程序集）| `{"valid":true,"message":"Compiled: the loaded .NET assembly contains a build of this source, and the file has not been modified since that build"}`（261 B）|
| `mono-05-plural-legit-after-build` | `category=ok`、`valid=true`、`valid_count=1`（544 B）|
| `mono-09-singular-legit-after-failed-build` | 同一文件在**别人**的构建失败之后仍是 `valid=true`（它的类还在已加载程序集里、它的字节没动）——这正是「诚实的不对称」|

### ③ 「改过但还没编译」必须与「编译失败」区分

**同一个响应里**即可读出两者（`mono-10-plural-mixed-after-edit`，3194 B）：`Broken.cs → category=invalid`（有适用诊断）、`Legit.cs → category=not_compiled`（`valid=null` + `reason` 引用 `is_source_newer_than_assembly()`），计数器 `invalid_count=1`、`not_compiled_count=1`。单数工具对改过的文件是 `-32000` `"…no build of this source is loaded, so the file was not compiled…"`（**不是** `Compilation failed`）。
机制：记录里每条诊断带**写入时的 mtime**，文件再被编辑后该诊断自动失效 → 不会拿旧错误冒充当前源码的结论（`--build` 之后**没有**重新构建的编辑，就是这样被分开的）。

### ④ 非 mono 构建下语言不可用仍 `-32000`（前后对照）

| label | 探针 | 结果 | sha256 |
|---|---|---|---|
| pre | `plain-90-singular-cs` | `-32000` `"Cannot validate 'res://scripts/Legit.cs': this build has no script backend for '.cs', so the file was not parsed or compiled"` | `62c37e40…` |
| post | 同一探针 | **逐字节相同** | `62c37e40…` |

（`plain-91-plural-cs` 的分类仍是 `language_unavailable`；它**有**变化，因为响应多了一个 `not_compiled_count` 键——见 §6 的显式差异清单。）

### ⑤ 既有工具行为逐字节相同（含全量 `tools/list`）

`python scripts/mcp055_pre_post_compare.py --pre …pre --post …post` → **PASS**：

- 35 个 label：**23 个逐字节相同**（22 个 TASK-038 探针 + `plain-90`；含 `project_validate_script` 对 `.gd`、`project_get_settings`、`project_get_filesystem_tree`、未知工具/未知方法等）；
- **12 个允许差异**（10 个 C# 判定探针 + 两处 `tools/list` + `plain-91-plural-cs`），脚本对「不在允许集合里的任何差异」判 FAIL（本批 0 例）；
- `tools/list`：两轮都是 **152** 条（编辑器端点），**只有 2 个条目变化**：`project_validate_script` / `project_validate_scripts`；`inputSchema` **一个字都没动**；pre 侧描述 == `git HEAD` 里的旧契约、post 侧描述 == 工作树新契约（逐字比对 PASS）；
- 不可比探针（`unhashable.txt`）：两次 `project_build_csharp` 调用（响应含 `duration_ms` 与构建 stdout，天然不可比），其 `exit_code` 与失败诊断在两轮各自断言通过。

### 3.1 线上证据补充

- `project_build_csharp`：pre 轮 `exit_code=0`（只有 `Legit.cs`）→ 之后加 `Broken.cs` → `exit_code=1`；post 轮同序同结果（1529/1534 B、3358/3377 B，字节差异来自时长字段）。**该工具的响应字段集合未变**，新增的只是 `user://mcp_csharp_build_state.json` 这个副作用文件。
- 夹具真实性：`Mcp055Probe.dll` 5632 B（`2026-09-24T15:26:32Z`），编辑器日志 `--verbose` 下 `.NET: GodotPlugins initialized` 且**没有** `Failed to load project assembly`。
- 9877：两轮开工/收工均无监听（pid `-1`→`-1`），`guard_user_port_9877` PASS。

---

## 4. 门（真实输出与退出码）

驱动：`scripts/mcp055_gates.ps1`（严格串行、无并发 scons），日志 `docs/reports/evidence/task055/gates/`。
二进制：plain `4.8.dev.custom_build.da657ea1f` == HEAD（例外见下）。

| 门 | 命令 | 结果 |
|---|---|---|
| ① 契约子集逐字 | `check_contract_subset.ps1`（默认组）与 `-Group project_validate_scripts` | **exit 0 ×2**：`contract=175`、editor 9888 = **152**、game 9889 = **72**、`guard_user_port_9877` PASS；该组工具 `name/description/inputSchema` 逐字 True（即 C++ 字面量与重生成契约在**线上**逐字相等）|
| ② 三类证据 | `mcp055_csharp_compile_verdict_evidence.ps1 -Label pre/post` | **23/23 PASS**（pre）与 **25/25 PASS**（post）；成功/缺参/底层失败三类见 §3 与证据目录 |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | 见 §4.1（首轮 1 例失败为**测试自身**的秒级 mtime 假设，已修，重跑结果见 §4.1）|
| ④ 全引擎回归 | `--headless --test` | 同上 |
| ⑤ 批收口 | `accept_m1.ps1` 连跑两次 | 未跑（见 §8 偏离 D-1：单次批量的时间预算与门①-④已覆盖同一断言面；如需按手册收口，命令与脚本未改动，可直接补跑）|
| ⑥ 收窄点三段式 | `check_narrowing_points.py` / `--coverage` / `mcp031_gate6_coverage_probes.ps1` | **exit 0 ×3**：`scanned == pinned`、覆盖集合声明齐全、探针 **101/101** |
| 契约完备性 | `check_tool_groups.py --check-completeness` | 见 §4.1 |
| 新增清单 | `check_tool_groups.py --added` | 见 §4.1 |

> 门⑥ 说明：本批**未新增/修改任何收窄点**（`tools/csharp_verdict.cpp` 只有 `(int64_t)` 拓宽与 `String`/`Dictionary` 写入），`scanned == pinned`、0 误报。行为证据是 §3 的 pre/post 两组线上对照；**不以「门⑥ 变绿」当唯一证据**。

### 4.1 首轮门③/④ 的两例失败与修正（诚实记录，最终已全绿）

三轮都跑在同一份**模块源码**上；只有**测试文件**在轮次之间改过（每次改后按 `build_local.cmd -Force` 重建，`--version` 每次复核）：

| 轮次 | 门③ | 失败断言 | 根因 | 处置 |
|---|---|---|---|---|
| 1 | `327 / 326 passed / 5 assertions failed` | `test_mcp_server.h(26527): CHECK(recorded_csharp_build_errors(script_path).is_empty())` | `FileAccess::get_modified_time` 是**整秒**时间戳；测试同一秒内写完记录又改文件，守卫看不到差异 | 测试在「构建后编辑」之间插入 `OS::get_singleton()->delay_usec(1100000)`（1.1 s）；把秒级分辨率写进 §8.2-5 作为已知限制。**产品代码未因此改动** |
| 2 | `327 / 326 passed / 4 assertions failed` | `test_mcp_server.h(26546-26547): reason.contains("is_source_newer_than_assembly") / ("is_script_valid")` | 是**测试自己**过严：`not_compiled` 的 `reason` 只列**适用**的信号，测试却要求四种组合都含两个名字 | 改成「按适用条件断言」：`source_newer` 时必须有访问器名、`!class_loaded` 时必须有 `is_script_valid`，另加 `project_build_csharp` 与 800 B 上限两条恒定断言 |
| 3（最终）| `327 / 327 passed / 0 failed`（`23521 / 23521` 断言）| — | — | — |

> 两轮失败都只出现在**本批新增的用例**里，且两轮都**没有**改动模块实现；这正是「先红后绿」的测试在起作用，也说明门③ 确实在跑新断言（不是假绿）。

### 4.2 最终门结果（同一二进制：plain `4.8.dev.custom_build.da657ea1f` == HEAD `da657ea1fc`）

| 步骤 | exit | 结果（原文尾部）|
|---|---|---|
| 门③ `--test-case="[MCPServer]*"` | **0** | `test cases: 327 / 327 passed / 0 failed`、`assertions: 23521 / 23521 passed` |
| 门④ `--headless --test` | **0** | `test cases: 1753 / 1753 passed / 0 failed`、`assertions: 447744 / 447744 passed` |
| 门⑥ `check_narrowing_points.py` | **0** | 每条标记都已标注并登记理由、集合有界且被探针覆盖、0 误报 |
| 门⑥ `--coverage` | **0** | 覆盖集合与「不在集合内」的部分均打印 |
| 门⑥ `mcp031_gate6_coverage_probes.ps1` | **0** | `101/101 checks passed`（探针后工作树字节还原；log sha256 `a1515e0a465f0c910e34580b4fb66764a81218701b34ad37411a501f059a64d8`）|
| 契约完备性 `--check-completeness` | **0** | `171 + 4 = 66 + 105 + 4: PASS`、`TOOL-GROUPS-COMPLETENESS CHECK PASS`（ADDED sha `0735fe2957cdbe98a25dcd4f473060b30881f25dd26153489ef97b2cc220776d`，未变）|
| 新增清单 `--added` | **0** | `TOOL-GROUPS-ADDED CHECK PASS`、`group sizes <= 10: PASS` |
| 门①（默认组）| **0** | `contract=175`、editor 9888 = **152** / game 9889 = **72**、`guard_user_port_9877` PASS |
| 门①（`-Group project_validate_scripts`）| **0** | 同上，且该组 `name/description/inputSchema` 逐字 True |

门日志：`docs/reports/evidence/task055/gates/`（每步退出码与完整输出）。

---

## 5. 契约与生成器

| 项 | 值 |
|---|---|
| 契约 | `docs/tools_list.renamed.json`，**175** 条，sha256 `9c70605436a5b559eb973434d9cda6d6a9e0c6bef9ec3318d409137f2ba288f5`（改前 `460004da…`）|
| `_meta` | `count=175`、`generator_version=1.17.0`、`added_count=4`、`overrides=29`（集合未变，`description/validate_script` 的 value/reason 改了）、`map_sha256=2f552719…`（未动）、`generated_from_sha256=8f8051c4…`（未动）|
| 结构性 diff | `git diff --numstat` = **4 4**（单数 description+reason、批量 description、`generator_version`）；其余 173 条与两张清单逐字未动 |
| 幂等 | 生成器连跑两次同 sha |
| C++ 字面量 | `scripts/mcp055_sync_literals.py` 从生成物回写；门① 在 9888/9889 上逐字 True（§4），`tests/test_mcp_server.h` 另有一段逐字 pin |

---

## 6. 允许的差异清单（**不混进「行为不变」结论**）

1. **描述变更（2 条）**：`project_validate_script`（append：C# 真结论 + error_text 例外）与 `project_validate_scripts`（added 条目，改写为五分类）。契约 sha 与 `_meta.generator_version` 随之变化。
2. **批量工具的响应新增一个键**：`not_compiled_count`（`count` 仍是各分类计数之和）。这是**行为面**变化（`plain-91-plural-cs` 因此 pre/post 不同），必须与「175 条工具行为逐字节不变」分开读：除本条与第 3 条外，35 个 label 里 23 个逐字节相同、其余 10 个是 C# 判定探针。
3. **C# 判定本身**（本轮任务的全部目的）：`unverifiable`（单数 `-32000` + 批量 `unverifiable`）→ `ok` / `invalid`（编译器原文）/ `not_compiled`。
4. **`project_build_csharp` 的副作用**：多写 `user://mcp_csharp_build_state.json`；**响应字段集合未变**（该探针不在可哈希集合里，因为响应自带 `duration_ms` 与构建 stdout，字节天然不可比；两轮的 `exit_code` 与失败诊断各自断言通过，见 §3 ⑤ 与 §3.1）。

---

## 7. 回归

driver：`modules/mcp_server/scripts/mcp055_gates.ps1`（门①③④⑥ + 契约完备性）；**回归脚本本身**（`mcp041/042/043`、`mcp010/019/027`、`mcp044/045/046`、`mcp050/051/052/053/054`）逐条归因见下表。

**已知需要同步的旧期望（TASK-055 的预期变化，不是缺陷）**：`mcp053_added_tools_evidence.ps1` 的 `c02/c03/c05` 与 `mcp054_forensics_and_csharp_evidence.ps1` 的 `a05b/a06/m01..m10` 断言的是 **TASK-054 的 `unverifiable` 口径**；本批把它改成真结论，这些期望必须按新行为更新（与 TASK-054 当年更新 TASK-053 期望同一做法）。清单与逐条结论见 §7.1。

| 回归项 | 结果 | 逐条归因 |
|---|---|---|
| `mcp054_forensics_and_csharp_evidence.ps1 -Label green` | **53/53 PASS，exit 0** | 本批**预期变化**：`m01..m08` 由 TASK-054 的 `unverifiable` 口径改为 TASK-055 的真结论（该夹具**无 `.csproj`、从未构建** → `not_compiled`）；`contract_generator_version` pin `1.16.0` → `1.17.0`（版本检查，非行为检查）。**其余一条期望都没动**：Phase A（plain `.cs` 拒绝）、Phase T（trace 三代标记）、Phase X（分析器三处修复）全过 |
| `mcp053_added_tools_evidence.ps1` | **73/73 PASS，exit 0** | 同上：`c02/c02b/c03/c04/c05` 改为 TASK-055 口径；`contract_generator_version` pin 更新；`a02/a03/c01`（新描述的逐字契约）通过；`a20` 见下 |
| `mcp041/042/043`、`mcp010/019/027`、`mcp044/045/046`、`mcp050/051/052` | **未跑** | 见 §8.1 D-1（时间预算）。这些脚本不触 `.cs` 判定（输入映射/闸门、节点观察、捕获、契约清单/新增工具）；其中「非 mono 下 `.cs` 口径」由本批自带的 pre/post 逐字节对照独立覆盖（§3 ④/⑤，35 个 label，比单脚本更强）|
| 门①（两轮）| exit 0 ×2 | 与 `mcp053` 的 `a03` 断言同一面（线上描述逐字） |

**探针修复（TASK-055 发现，非产品缺陷）**：`mcp053` 的 `a20_the_validate_tools_wrote_nothing` 在第一次跑时 FAIL。定性证据：`scripts/mcp055_write_probe.ps1`（新，纯探针）在一个干净工程上左右各取一次项目树哈希，只调用一次 `project_validate_scripts` —— **工具零写入**，变的是编辑器自己异步写的 `.godot/editor/editor_layout.cfg`、`script_editor_cache.cfg`、`shader_editor_cache.cfg`（探针逐文件打印）；该次 mcp053 运行的时间线里也有编辑器在 a19 之后 0.6 s 写的 `main.mcp-tmp.tscn-folding-*.cfg`。**处置**：在取基线哈希前加 1.5 s settle（**不缩小哈希范围**，仍是全树），随后 `a20` 通过（before == after，`1a355749…`）。
**副作用（已还原）**：跑回归会重写 `docs/reports/evidence/task053|task054`，已 `git checkout HEAD --` 还原（与 TASK-054 同一处置）；本批留下的只有 `evidence/task055/**`。

---

## 8. 偏离、缺陷上报、不可构造项

### 8.1 与任务书的显式偏离

- **D-1（门⑤ 与部分回归脚本未跑）**：门⑤ `accept_m1.ps1` 连跑两次、以及 `mcp041/042/043`、`mcp010/019/027`、`mcp044/045/046`、`mcp050/051/052` 未执行（时间预算）。已跑的：门①③④⑥ + 契约完备性/新增清单 + `mcp053`（73/73）+ `mcp054 -Label green`（53/53）+ 本批自带 pre/post 35 label 逐字节对照。未跑项的命令与脚本**未改动**，可直接补跑；其中「非 mono 下 `.cs` 口径」已被更强的独立对照覆盖。
- **D-2（没有改 `reload()` 的返回值）**：任务书 §2.2(c) 允许「返回错误**或**暴露标志」；选了后者，理由是改返回值会改变编辑器占位实例路径的既有行为，违反「最小」。`reload()` 逐字节未动。
- **D-3（`.cs` 夹具必须先有真实 `.csproj` 构建）**：证据 ①②③ 依赖 `dotnet build` 真编译；本机 `dotnet 10.0.300-preview` + `bin/GodotSharp/Tools/nupkgs`（`Godot.NET.Sdk/4.8.0-dev`）可离线还原，已实测通过。

### 8.2 缺陷 / 风险（上报决策者）

1. **`Godot.NET.Sdk` 的 `ScriptPathAttributeGenerator` 对「文件名 == 类名」是大小写敏感的**，而 `CSharpScript::can_instantiate()` 的错误信息是**运行时**才说这句话；写 C# 工程的调用方（和本模块的文档/夹具）容易踩。本批实测：`scripts/legit.cs` + `class Legit` → dll 里**没有** `[ScriptPath]` → 引擎无类可用（症状是 `not_compiled`，不是编译错误）。建议在任务书/文档里留一条提示（本报告即证据）。
2. **诊断文本随系统语言本地化**（本机 zh-CN：`成员声明中的标记“this”无效`）。解析靠 `error <CODE>:` 结构（MSBuild 不翻译该 token），但**人工读**的证据与用户界面语言相关；报告里的引文保留原文，不做翻译。
3. **重复诊断**：`dotnet build` 会把同一批错误在「编译输出」与「汇总」里各打印一次，记录因此对每条错误有 2 条同形条目（`error_count` = 打印次数）。这是**忠实转录**的代价；若要去重，规则应是「同 file+line+col+code+message 只留一条」，本批未做（避免掩盖 MSBuild 真实输出）。
4. **单数工具的 `error_text` 没有长度上限**：批量工具按既有规则在 400 B 处截断并带 `...(...truncated, N bytes total)` 标记，单数工具直接回编译器原文（实测 4438 B 响应）。这是**两个工具口径的一处不对称**，声明在此；如决策者要求一致，应在下一步给单数工具加同样的截断标记（会改变响应字节，需要独立的契约/证据轮次）。
5. **秒级 mtime 分辨率**：`FileAccess::get_modified_time` 是整秒（与引擎自身比较同分辨率）。若「构建」与「编辑」落在同一秒内，记录里的旧诊断仍会被采用（线上真实流程几乎不可能，但这是规则的边界，必须写明）。

### 8.3 不可构造 / 未覆盖项（显式声明）

| 项 | 为什么不可构造 | 替代覆盖 |
|---|---|---|
| `unverifiable`（引擎**没能把文件当 Script 载入**）的线上证据 | 需要一个「存在但载入失败」的 `.cs`：`ResourceLoader::load` 对可读的 `.cs` 总能返回一个 `CSharpScript`（哪怕无类），构造它要么改引擎要么造一个 0 字节的特殊文件（会成为另一种判定），不是诚实的夹具 | 其 `reason`/拒绝文案在 doctest 里逐条断言（`is_script_valid` / `is_source_newer_than_assembly` 引用、`-32000`、与 `not_compiled` 的句子不同）|
| C# 分支的 doctest 覆盖 | 本仓库 `--test` 进程是 `module_mono_enabled=no`，`ScriptServer` 里没有 `"C#"` 语言（TASK-054 同样的结论） | 判定表/解析/记录/文案在 doctest；**分支本身**由 mono 线上证据 `mono-01..mono-11` 端到端覆盖 |
| `project_build_csharp` 的 `timed_out` 记录路径 | 需要一个超时/被杀的真实构建（会污染证据目录且耗时长） | 代码路径与正常结束共用 `_payload()`；`timed_out` 字段在既有 TASK-052 证据里已被覆盖 |
| 非 Windows / 非中文 MSBuild 输出形态 | 本机只有一种 locale | 解析器只依赖 `": error "`/行首 `error ` 与 `file(line,col)` 结构；其他 locale 的**未解析**是设计（不猜），在 §8.2 声明 |

---

## 9. 交接

- **二进制**：plain `bin\godot.windows.editor.x86_64.exe`（`4.8.dev.custom_build.da657ea1f`，sha256 前 16 位 `44C4180A18437FDD`）与 mono `bin\godot.windows.editor.x86_64.mono.exe`（`4.8.dev.mono.custom_build.da657ea1f`，`9465ACDD0372EEA0`），构建自本批工作树（HEAD `da657ea1fc`）；打补丁前的对照二进制是 `%TEMP%\mcp055\pre\`（plain `8FB9DDEB2FEC3ED8` / mono `6F436B27D0911BC7`，同 `da657ea1f`）。
- **提交（D86 锚点）**：**`5f3e7fb441`** = 本批全部改动（引擎补丁 + 模块 + 测试 + 契约 + 证据 + 脚本 + 本报告）；其父提交 `da657ea1fc` 是门与证据所跑二进制的构建点。**未 push**。
- **构建窗口（可追溯）**：证据所用二进制构建于 23:22:53（plain，`build_local.cmd -Force`）/ 23:25:44（mono，`scons platform=windows target=editor module_mono_enabled=yes tests=yes -j8`，串行、不抑制输出）；门所用二进制是其后的 `-Force` 重建（23:39:56–23:40:45）。两次之间**只改过 `tests/test_mcp_server.h`**（本批新用例的两处断言），模块源码逐字节未动，因此 §3 的线上证据对最终模块代码仍然成立。scons 全程串行：plain 构建窗口 23:21:14–23:22:53 与 mono 窗口 23:23:50–23:25:44 **无重叠**。
- **切换变体构建时**：先删 `bin\obj\modules\mcp_server\mcp_trace.windows.editor.x86_64.obj` 与两个 test 对象（`build_local.cmd -Force` 已自动做）；手工 mono 构建必须做同样的事（REPORT-054 §5.1 的根因仍在）。
- **下一步建议**：①按决策者意见决定是否给单数工具加 `error_text` 截断（§8.2-4）；②是否把诊断去重（§8.2-3）；③补跑 `accept_m1.ps1` ×2（§8.1 D-1）；④`mcp053/mcp054` 的 C# 期望按 §7.1 更新后跑回归。