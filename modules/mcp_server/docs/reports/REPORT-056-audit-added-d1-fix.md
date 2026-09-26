# REPORT-056 — 收口 `REPORT-AUDIT-ADDED` 的 D1/D2/D3 + 补跑 TASK-055 声明未跑的回归

> **D86 提交锚点**：全部门与证据都跑在**工作树 HEAD `4e3de109037ffa5d17b1d08f9df2876810bb656b`** 上
> （`--version` = `4.8.dev.custom_build.4e3de1090`，前缀 == `git rev-parse --short HEAD` = `4e3de10903`；
> mono = `4.8.dev.mono.custom_build.4e3de1090`）。**实现提交 = `75adcdcce89fb55a4d319d0ff8bd5db8bd456536`**
> （`fix(mcp_server): TASK-056 D1 no-claim for language_unavailable, D2 version, D3 separator`，其父提交即 `4e3de10903`；
> 复现入口见 §10，代码落点见 §4），本报告随其后一个提交落盘。下文每条结论都是本执行方在本锚点上自己跑出来的；
> 引用 `REPORT-*` 只作为**被修正对象的原始记录**，不作为行为证据。
> 任务书：`docs/tasks/TASK-056-audit-added-d1-fix.md`；规范依据：`TASK-053 §2.1`、`TASK-054`、`DESIGN-DETAIL` §26/GDR-25/§22。
> 端口纪律：9877 全程无监听（每步 `pid_before = pid_after = -1`，`guard_user_port_9877` PASS）；只用 9888；
> **未启动/未杀/未重启任何 9877 进程**；**禁止 push** 遵守；**scons 全程串行**（plain → mono → plain，无重叠）。

---

## 0. 结论

| 项 | 结论 | 一句话 |
|---|---|---|
| **D1（阻断）** | **已修** | `language_unavailable` 条目不再发布 `valid: false`，改为 `valid: null` + `category` + `reason` + `suggestion`；单数与批量口径一致（单数仍 `-32000` 不声称） |
| **D2（文档漂移）** | **已修** | `docs/tool-groups-added.json` 的 `source.entries` 版本串同步到**当前生成器版本**；只改了这一行 |
| **D3（外观）** | **已修** | `project_build_csharp` 的 `command` 用单一分隔符；真实执行路径与 `exit_code` 未变（前后各一次真实 `dotnet build`，均 `exit_code=0`） |
| 契约 | **175 条不变** | `docs/tools_list.renamed.json` sha256 **`9c706054…`（与 TASK-055 相同，逐字节未动）**；生成器未改 |
| 门 | **全绿** | 五道门 + 门⑥ 三段式 + `--check-completeness`/`--added` 共 9 步全 exit 0（§6） |
| 回归 | **15/15 exit 0** | `accept_m1` ×2（22/22，两跑 PASS 清单**逐行相同**）+ TASK-055 声明未跑的全部脚本（§7） |

---

## 1. D1 —— `language_unavailable` 不得发布 `valid: false`（阻断，已修）

### 1.1 根因（代码腿）

`MCPValidateScriptVerdict` 的一个 `valid` 字段被两个工具共用，而“不声称”的 JSON 形状只挂在了
`unverifiable` / `not_compiled` 两个分类上：

| 位置（修前） | 事实 |
|---|---|
| `tools/project_validate_scripts.cpp:154`（`_item()`） | `if (category == "unverifiable" \|\| category == "not_compiled")` 才走 `entry["valid"] = Variant()`（JSON `null`）+ `reason`；`language_unavailable` **掉到** `entry["valid"] = p_verdict.valid`（`project_read_files.cpp` 里该分类恒 `false`）→ 线上逐字 `"valid":false` |
| `tools/project_read_files.cpp:494`（`validate_script_source()` 的 `LANGUAGE_UNAVAILABLE` 分支） | `verdict.valid = false;` 且**不设 `reason`**（当时没有该分类的 reason 函数）；单数工具靠 `project_read_files.cpp:595` 提前转成 `-32000` 拒绝，所以缺陷只在批量工具上暴露 |

即：**同一个缺陷面在 TASK-054 只补了 `unverifiable` 一半**（与 `REPORT-AUDIT-ADDED` §7 D1 的判定一致）。

### 1.2 修法（逐处）

| 文件 | 改动 |
|---|---|
| `tools/project_read_files.h` | 新增声明 `String validate_script_language_unavailable_reason(const String &p_path, const String &p_extension);`（`valid` 不声称的**引擎依据**）；`MCPValidateScriptVerdict::reason` 的注释扩到三个“无结论”分类 |
| `tools/project_read_files.cpp` | 新增 `validate_script_language_unavailable_reason()`：逐字给出 `ScriptServer::are_languages_initialized()` / `ScriptServer::get_language_for_extension("<ext>")`（`core/object/script_language.h`）与“没有后端是本构建的属性，不是对该文件的判决”；`validate_script_source()` 的 `LANGUAGE_UNAVAILABLE` 分支与 `validate_csharp_script_source()` 的 `#else` 分支都填上 `verdict.reason`（`valid` 字段保留 `false` 只作惰性默认值，注释写明线上不发布） |
| `tools/project_validate_scripts.cpp` | `_item()` 的“不声称”分支条件加上 `language_unavailable`，三个分类统一 `valid: Variant()`（JSON `null`）+ `reason` + `message` + `suggestion`；`suggestion` 按分类分派（`language_unavailable` 用 `validate_script_language_unavailable_error()`，其余用 `validate_script_verdict_refusal()`）——原先把 `language_unavailable` 的 suggestion 放到 `valid` 之后的死代码块已删除 |
| `tools/project_validate_scripts.h` | 注释里的分类清单补全为五个，并写明“只有 `ok`/`invalid` 带布尔 `valid`，其余三个发布 `valid: null` + `reason`” |
| `tests/test_mcp_server.h` | **先红后绿**：把 `CHECK((bool)cs["valid"] == false)` 换成 `REQUIRE(cs.has("valid")) + CHECK(cs["valid"].get_type() == Variant::NIL)` + `reason` 逐条断言（`legit.cs` 与 `shader.gdshader` 都加）。旧的布尔断言**在 `null` 上也成立**，这正是缺陷藏身处——报告里显式记下这一点 |

### 1.3 红 → 绿（真实输出）

红（改动前的实现 + 新测试，`--test-case='*classifies three categories*'`）：

```
.\modules/mcp_server/tests/test_mcp_server.h(25834): ERROR: CHECK( cs["valid"].get_type() == Variant::NIL ) is NOT correct!
  values: CHECK( 1 == 0 )
.\modules/mcp_server/tests/test_mcp_server.h(25836): FATAL ERROR: REQUIRE( cs.has("reason") ) is NOT correct!
.\modules/mcp_server/tests/test_mcp_server.h(25837): ERROR: CHECK( String(cs["reason"]).contains("get_language_for_extension") ) is NOT correct!
.\modules/mcp_server/tests/test_mcp_server.h(25838): ERROR: CHECK( String(cs["reason"]).contains("legit.cs") ) is NOT correct!
.\modules/mcp_server/tests/test_mcp_server.h(25851): ERROR: CHECK( shader["valid"].get_type() == Variant::NIL ) is NOT correct!
.\modules/mcp_server/tests/test_mcp_server.h(25852): FATAL ERROR: REQUIRE( shader.has("reason") ) is NOT correct!
.\modules/mcp_server/tests/test_mcp_server.h(25853): ERROR: CHECK( String(shader["reason"]).contains("get_language_for_extension") ) is NOT correct!
[doctest] test cases: 1 | 0 passed | 1 failed | 1755 skipped
[doctest] assertions: 63 | 56 passed | 7 failed | Status: FAILURE!
```

绿（同一命令，修后）：`test cases: 1 | 1 passed | 0 failed`、`assertions: 63 | 63 passed | 0 failed`、`Status: SUCCESS!`。

### 1.4 证据（任务书 §1 的 ①②③）

**证据目录**：`docs/reports/evidence/task056/`；“修前”字节一律取自**仓库内已跟踪的** TASK-055 记录
（`docs/reports/evidence/task055/post/plain-91-plural-cs.response.json`，即修复前的紧邻提交），因此不依赖任何已被覆盖的二进制。

**① 同一请求的响应逐字前后对照**（`python scripts/mcp056_pre_post_compare.py` → **`PRE_POST_COMPARE=PASS`**，
请求体逐字相同：`{"paths":["res://scripts/Legit.cs","res://scripts/plain.gd"]}`，label `plain-91-plural-cs`）：

| 字段 | 修前（`task055/post`） | 修后（`task056`） | 判定 |
|---|---|---|---|
| `category` / `language` / `path` / `message` / `suggestion` | 逐字 | **逐字未动** | PASS（比较器逐字段断言） |
| `valid` | `false` | **`null`**（键仍在） | PASS |
| `reason` | 键不存在 | 新增，含 `get_language_for_extension` + `ScriptServer::are_languages_initialized()` | PASS |
| `count`/`valid_count`/`invalid_count`/`unavailable_count`/`unverifiable_count`/`not_compiled_count`/`returned`/`truncated`/`dropped`/`errors_only`/`limits` | — | **全部逐字未动** | PASS |
| `plain.gd` 条目（`ok`/`valid:true`） | — | **逐字未动** | PASS |
| 线上字节 | 971 B | 1369 B（+`reason`，-`false`→`null`） | — |

响应 sha256：修后 `48d2ef13d75f1976a0bcfcc6a0ff62dd9be57ac2b7024b2e942d7072903d7371`；
同一请求**重复一次**得到**同一 sha**（`plain-91b-plural-cs-repeat`）。
旁证（独立第三方记录）：审计方的修前字节 `%TEMP%\audit-added\evidence\v05_plural_mixed.response.json`
sha256 `8dd790dd2b7be478de342e5892b4efb577552c8c10a735f949f153ec21f8e853`，与 `REPORT-AUDIT-ADDED` §7 D1 逐字一致
（我 `certutil` 复核过），它记录的就是同一条 `"valid":false`。

**② 两个工具对同一文件结论一致**：单数 `project_validate_script{path:res://scripts/Legit.cs}` →
`-32000`、`message` 含 `not parsed or compiled`、`data.suggestion` 含 `module_mono_enabled=yes`、**响应里没有 `valid` 键**；
批量条目的 `suggestion` 与单数的 `data.suggestion` **逐字相等**（脚本断言 `==` 为 True）。
单数响应 sha256 `62c37e40eaee6f53a95e204030777cfbc8148a90180ec9ecf17de4a4c65b3136`——与
`REPORT-055` §3 ④ 记录的修前/修后同值 `62c37e40…` 相同，证明**单数工具一个字节都没动**（本批只改批量侧）。

**③ `count`/各计数器语义自洽**：`count=2, valid_count=1, invalid_count=0, unavailable_count=1, unverifiable_count=0,
not_compiled_count=0`，且 `count == 五者之和`（线上断言 PASS）。
批量单文件探针（`paths:["res://scripts/Legit.cs"]`）在 `mcp053` 回归里同样得到 `unavailable_count=1`、`valid: null`、`reason` 存在（73/73 PASS）。

**旁证（既有间歇崩溃被守卫接住，现场第 5 次）**：重跑 plain 相位时，`--import` 第一次以
`-1073741819 (0xC0000005)` 结束、日志尾部为 `EditorNode::is_cmdline_mode (editor\editor_node.cpp:6732)` 的
`ERROR: Parameter "singleton" is null.`；`Import-McpProject` 打印了命令/退出码/工程路径/日志尾部并在**第 2 次尝试** exit 0
（`import[import056] attempt 2/3 exit=0`）。这是 TASK-028 已归因的引擎侧间歇崩溃（历史 4 次，无法复现、无法归因到本模块），
本批的每次导入都走守卫的“校验退出码 + 有界重试 + 可诊断输出”，结论不依赖它是否复现。

### 1.5 契约描述：**无需改动**（这是判断，不是省略）

两条描述的**现行文字已经写的就是要修成的口径**，所以 D1 的修复**不动契约、不动生成器、不动指纹**：

* 批量（`tools/project_validate_scripts.cpp:367`，即 `ADDED_TOOLS` 的逐字副本）：
  “…`language_unavailable` (this build has no script backend for the extension) and `unverifiable` (the engine could not load the file
  as a Script resource); **`valid` is published only for `ok` and `invalid`**, and `count` is always the sum of the per-category counters.”
* 单数（`tools/project_read_files.cpp:930`）：“…本构建不含该语言的脚本后端时（例如 module_mono_enabled=no 的构建里的 .cs）
  **不借用别的语言解析、也不给出 valid，而是以 -32000 拒绝**并在 data.suggestion 里说明该用哪个构建或文件…”

修复前的实现与这两句**矛盾**（描述是对的、实现是错的）→ 修实现即可。证据：契约 sha256 前后同为 `9c706054…`，
`git status` 里 `docs/tools_list.renamed.json` **未被修改**；生成器连跑两次同 sha，且 `fc /b` 判定
`docs/tools_list.renamed.json` == 生成器输出（生成器自报 `output sha256 = 9c706054…`、`input tools = 174 / output tools = 175 / added = 4`）。
**未新增 `DESCRIPTION_OVERRIDES`**，因此 `overrides = 29` 不变、`_meta.generator_version` 不变。

---

## 2. D2 —— `docs/tool-groups-added.json` 的生成器版本漂移（已修）

```diff
-    "entries": "... ADDED_TOOLS (generator v1.15.0, TASK-052 section 1 + TASK-053 section 2.1/2.2)",
+    "entries": "... ADDED_TOOLS (generator v1.17.0, TASK-052 section 1 + TASK-053 section 2.1/2.2)",
```

* **只改这一行**：`git diff -- modules/mcp_server/docs/tool-groups-added.json` = `2 +-`（1 行替换），无其它字段变化。
* **偏离任务书字面（显式声明）**：任务书写“v1.15.0 → **1.16.0**”，那是审计（`REPORT-AUDIT-ADDED`，提交 `da657ea1fc`）时的实际版本；
  TASK-055（提交 `5f3e7fb441`）随后把生成器升到 **`1.17.0`**（`scripts/gen_renamed_contract.py:368` `GENERATOR_VERSION = "1.17.0"`）。
  D2 的**意图**是“该字段必须等于当前生成器版本”，故写 `v1.17.0`；写 `1.16.0` 会立刻造成**第二次同样的漂移**。
  依据：`REPORT-055` §5（`_meta.generator_version=1.17.0`）+ 我在本锚点重跑生成器的自报版本。
* 机器校验未被削弱：`check_tool_groups.py --added` exit 0（`manifest = contract _meta.added_tools, both directions: PASS`、
  四个组 `channel/scope/mutating/verb` 一致、`group sizes <= 10: PASS`）；该字段本身是**自述**，不在机器校验面内（与审计 D2 的定级一致）。
* 清单文件 sha 因此变化（`fb15a9f43861f080ed9f4c29d98bd85f62f48ca03e503e57011fcc0cace4fcd3`，
  TASK-055 记录为 `0735fe29…`）——**这正是本次要改的那个文件**，不是契约。

---

## 3. D3 —— `project_build_csharp` 的 `command` 分隔符（已修）

### 3.1 根因

`tools/project_csharp_build.cpp` 用 `directory.path_join("dotnet.exe")` 拼可执行路径，而
`String::path_join`（`core/string/ustring.cpp:5057-5065`）**只把结尾的 `'/'` 当作已有分隔符**：

```cpp
if (operator[](length() - 1) == '/' || (p_file.size() > 0 && p_file.operator[](0) == '/')) { return *this + p_file; }
return *this + "/" + p_file;   // 结尾是 '\' 时不识别，于是无条件加一个 '/'
```

Windows 的 `PATH` 项通常写作 `C:\Program Files\dotnet\`（结尾反斜杠）→
`C:\Program Files\dotnet\` + `/` + `dotnet.exe` = **`C:\Program Files\dotnet\/dotnet.exe`**。
**执行本身成功**（`ChildProcess::start()` 拿的是 argv 分离的路径），所以这只是**外观/可读性**缺陷。

### 3.2 修法与取舍（选哪种分隔符、为什么）

新增**可测的纯函数** `MCPTools::csharp_executable_path(directory, name, p_windows)`（`tools/project_csharp_build.{h,cpp}`），
`find_dotnet_executable()` 改为调用它：

1. 先把目录里的分隔符**统一到运行平台的那一种**（Windows：`'/'`→`'\'`；POSIX 反向）——否则
   `C:/Program Files/dotnet/` 这类同样是合法 PATH 拼写仍会混用；
2. 去掉结尾的全部分隔符（`path_join` 只认一个 `'/'`，这里是有界循环，多个也处理）；
3. **插入恰好一个平台原生分隔符**；目录为空（或仅空白）时直接返回名字，不产生前导分隔符。

**选“Windows 用反斜杠”的理由**：这个值是**交给操作系统的可执行文件路径**（`ChildProcess::start()` → `CreateProcessW`），
不是模块对外的 `res://` 工程路径；Windows 原生的可执行路径就是反斜杠，且反斜杠拼法**不要求** Windows API 兼容 `/`
（前向斜杠虽可用，但把“能跑”建立在文件系统容错上不是必要的风险）。POSIX 分支保持 `/`。
`p_windows` 作为**参数**传入（而不是函数内读 `OS`），使两个分支都能在同一个 `--test` 进程里被 doctest 钉住。

真实执行路径与结果**未变**：`ChildProcess::start()` 的 argv 与 `exit_code` 前后都是 `0`（§3.3）。

### 3.3 红 → 绿（真实输出）

红（把旧表达式 `p_directory.path_join(p_name)` 先原样抽成同签名助手 + 新测试；`--test-case='*TASK-056*'`）：
**8 条断言失败**，首条即
`CHECK( measured == "C:\\Program Files\\dotnet\\dotnet.exe" ) is NOT correct!`、
`CHECK_FALSE( measured.contains("/") ) is NOT correct!`；`test cases: 1 | 0 passed | 1 failed`、`assertions: 12 | 4 passed | 8 failed`。
绿（修好函数体后）：`test cases: 1 | 1 passed`、`assertions: 12 | 12 passed`、`Status: SUCCESS!`。

### 3.4 线上证据（真实 `dotnet build`，mono 构建）

`docs/reports/evidence/task056/mono-build-csharp.response.json`（`scripts/mcp056_evidence.ps1 -Phase mono`，**11/11 PASS**）：

| 项 | 修前（`task055/post/mono-03-build-succeeds`） | 修后（`task056/mono-build-csharp`） |
|---|---|---|
| `command` 头 | `C:\Program Files\dotnet\/dotnet.exe build …` | **`C:\Program Files\dotnet\dotnet.exe build …`**（无 `\/`、无 `/\`、无双写） |
| `commands[0]` | 同 `command` | 同 `command`（脚本断言 `-ceq`） |
| `exit_code` / `exit_codes` | `0` / `[0]` | **`0` / `[0]`** |
| 真实产物 | `Mcp055Probe.dll` | `Mcp056Probe.dll`（`.godot\mono\temp\bin\Debug\`，`Test-Path` True） |
| 解析出的可执行 | — | `Get-Command dotnet` = `C:\Program Files\dotnet\dotnet.exe`（`Test-Path` True），`command` 以它 + 空格开头 |

比较器（`mcp056_pre_post_compare.py`）逐条 PASS：`before_had_a_mixed_separator`、`after_has_no_mixed_separator`、
`the_executable_is_the_same_file`（`C:\Program Files\dotnet\/dotnet.exe` vs `C:\Program Files\dotnet\dotnet.exe`）、
`the_arguments_are_unchanged`（`<…>.csproj -c Debug`）、`after_exit_code_0`、`the_directory_is_the_same`。
响应 sha256 = `a1010292b6918eea18e88f7cf85dfc6205ac9fe0d4641af2d0d9d0320bedaa84`（1505 B；两次 mono 相位运行的
`command`/`exit_code`/字节数完全相同，sha 只随 `duration_ms` 与 MSBuild stdout 的耗时数字变化——这正是该响应不可跨轮次哈希的原因，
`REPORT-055` §3 ⑤ 已把 `project_build_csharp` 登记为 `unhashable`）。

---

## 4. 改动清单（10 个跟踪文件，`git diff --stat` = 142 insertions / 36 deletions）

| 文件 | 行/量 | 内容 |
|---|---|---|
| `tools/project_read_files.h` | +未跟踪 | 新 reason 声明；`reason` 注释扩到三个分类 |
| `tools/project_read_files.cpp` | +17 | 新 `validate_script_language_unavailable_reason()`；两处 `language_unavailable` 判决填 `reason` |
| `tools/project_validate_scripts.cpp` | 32 行重排 | `_item()` 三个分类统一 `valid: null`；suggestion 按分类分派 |
| `tools/project_validate_scripts.h` | 注释 | 分类清单/`valid` 口径写清 |
| `tools/project_csharp_build.h` / `.cpp` | +12 / +21 | 新 `csharp_executable_path()`（纯函数）+ `find_dotnet_executable()` 调用它 |
| `tests/test_mcp_server.h` | +54 | D1 断言强化（`legit.cs` / `shader.gdshader`）+ 新 `TEST_CASE`（D3 分隔符矩阵 12 断言） |
| `docs/tool-groups-added.json` | 1 行 | D2 版本串 |
| `scripts/mcp053_added_tools_evidence.ps1` | 12 行 | 期望按新口径（`$null -eq $csItem.valid` + `reason`） |
| `scripts/mcp055_csharp_compile_verdict_evidence.ps1` | 4 行 | 同上（该脚本的 `plain_plural_cs_is_language_unavailable`） |
| **新增** | — | `scripts/mcp056_evidence.ps1`（纯 ASCII）、`scripts/mcp056_pre_post_compare.py`、`scripts/mcp056_gates.ps1`、`scripts/mcp056_regression_battery.ps1`、`docs/reports/evidence/task056/**`、本报告 |

**未改动**：`docs/tools_list.renamed.json`（sha256 恒 `9c706054…`）、`scripts/gen_renamed_contract.py`、`docs/tool-rename-map.json`、
`docs/tool-groups{,-b2..-b5}.json`、引擎源码（`modules/mono/**` 等）、hof-rs 仓库。
**收窄点**：本批未新增/修改任何收窄写值点（改动只有 `String`/`Variant`/布尔赋值与路径拼接），门⑥ `scanned=75 pinned=75`、0 误报。

---

## 5. 门前的构建纪律（R-1）

| 次序 | 命令 | 结果 |
|---|---|---|
| 1 | `modules\mcp_server\scripts\build_local.cmd -Force`（plain，`tests=yes`，从 cmd 启动） | exit 0，`--version` = `…custom_build.4e3de1090` == HEAD `4e3de10903` |
| 2 | 同上（D1 实现后、D3 红） | exit 0 |
| 3 | 同上（D3 修好后） | exit 0 |
| 4 | 删 `mcp_trace`/两个 test 对象后 `scons platform=windows target=editor module_mono_enabled=yes tests=yes -j8`（**串行、未抑制输出**，`INFO: Time elapsed: 00:01:38.87`） | exit 0，mono `--version` = `4.8.dev.mono.custom_build.4e3de1090` |
| 5 | `build_local.cmd -Force`（门用的 plain 二进制，mono 变体切换后按 PLAYBOOK 强制重建） | exit 0，`--version` 复核 == HEAD |

无并发 scons：窗口 1→2→3 与 4 与 5 严格串行、互不重叠；只出现一条既有告警
`editor_node_setup.h(36): warning C4099`（与本批无关）。

---

## 6. 门（真实输出与退出码；日志 `docs/reports/evidence/task056/gates/`）

| 门 | 命令 | exit | 结果（原文尾部） |
|---|---|---|---|
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **0** | `test cases: 328 / 328 passed / 0 failed`、`assertions: 23541 / 23541 passed`（TASK-055 为 327 → **+1 即本批新 `TEST_CASE`**） |
| ④ 全引擎回归 | `--headless --test` | **0** | `test cases: 1754 / 1754 passed / 0 failed`、`assertions: 447764 / 447764 passed`（+1 用例） |
| ⑥ 收窄点 | `check_narrowing_points.py` | **0** | `scanned : 75`、`pinned : 75`、PASS（11 条行号漂移是既有注记，非失败） |
| ⑥ `--coverage` | 同上 + `--coverage` | **0** | 打印已声明集合与集合外部分 |
| ⑥ 探针 | `mcp031_gate6_coverage_probes.ps1` | **0** | `101/101 checks passed`（`log sha256=a1515e0a465f0c910e34580b4fb66764a81218701b34ad37411a501f059a64d8`，与 TASK-055 相同；探针后树字节还原） |
| 契约完备性 | `check_tool_groups.py --check-completeness` | **0** | `contract entries = 175`、`171 + 4 = 66 + 105 + 4: PASS`、`175 条各恰好一桶: PASS`、`TOOL-GROUPS-COMPLETENESS CHECK PASS` |
| 新增清单 | `check_tool_groups.py --added` | **0** | `manifest = contract _meta.added_tools, both directions: PASS`、`group sizes <= 10: PASS`、`TOOL-GROUPS-ADDED CHECK PASS` |
| ① 契约子集 | `check_contract_subset.ps1`（默认组） | **0** | `contract=175`、editor 9888 = **152** / game 9889 = **72**、`guard_user_port_9877` PASS、`3/3 checks passed` |
| ① 契约子集 | `check_contract_subset.ps1 -Group project_validate_scripts` | **0** | 同上，且该组 `name/description/inputSchema` 逐字 True |

**门⑤（每批收口）**：`accept_m1.ps1` 连跑两次，各 `22/22 cases passed`、exit 0，两次 PASS 清单
`Compare-Object` **differing_lines = 0**（`docs/reports/evidence/task056/regression/accept_m1_pass_list_compare.txt`）。
**门②**：见 §1.4（成功/底层失败）与 §3.4（成功 + 真实产物）；缺参一类由 `mcp053` 的 `-32602` 用例组与既有探针覆盖。

---

## 7. 补跑 TASK-055 声明未跑的回归（`REPORT-055` §8.1 D-1）

驱动：`scripts/mcp056_regression_battery.ps1`（把每个脚本作为独立 `powershell -File` 子进程**串行**执行，
各自日志 `docs/reports/evidence/task056/regression/<name>.log`，退出码汇总 `summary.txt`）。
**15/15 步 exit 0**（含我追加的 `mcp053`，理由见下）。

| 回归项 | exit | 真实结果 | 逐条归因 |
|---|---|---|---|
| `accept_m1.ps1`（第 1 次） | 0 | `22/22 cases passed` | 端口 9877 无监听（pid -1→-1）；契约 175、editor 152 / game 72；工具集由六份清单派生（含 `tool-groups-added.json`） |
| `accept_m1.ps1`（第 2 次） | 0 | `22/22`，与第 1 次 **PASS 清单逐行相同** | 同一次构建内跨进程重启的 `tools/list` 逐字节一致（case20）仍成立 |
| `mcp041_gates.ps1` | 0 | `DONE`（内含 `regress_mcp040_racing EXIT 0 (47s)`） | 与本批无关；唯一“tree dirty”提示列出的正是**本批的 10 个已改文件**，不是它自己引入的改动 |
| `mcp042_gates.ps1` | 0 | `DONE`（同上形态，48s） | 同上 |
| `mcp043_gates.ps1` | 0 | `DONE`（同上形态，48s） | 同上 |
| `mcp010_b2_observation_evidence.ps1` | 0 | `phase game: 29/29 checks passed` | 观察/延迟通道未受影响 |
| `mcp019_b4_evidence.ps1` | 0 | 全 PASS（含 `H1_user_editor_port_9877_guard`） | B4 节点读族未受影响 |
| `mcp027_object_shape_and_paths_evidence.ps1` | 0 | `phase green: 60/60 checks passed` | 对象形状/路径归一；`log sha256=ecbc86c7…` |
| `mcp044_capture_evidence.ps1` | 0 | `40/40 checks passed (phase editor)` | 捕获通道 |
| `mcp045_pixel_compare_cost.ps1` | 0 | `15/15 checks passed` | 成本探针 |
| `mcp046_capture_encode_cost.ps1` | 0 | `23/23 checks passed` | 编码成本 |
| `mcp050_parameter_guidance_evidence.ps1` | 0 | `probes: 29`，`summary sha256=4158dc49…` | 参数指引；**不触 `.cs` 判决口径** |
| `mcp051_b_tier_evidence.ps1` | 0 | `probes: 25 / facts: 8`，`summary sha256=7907836a…` | B 层证据；同上 |
| `mcp052_added_tools_evidence.ps1` | 0 | `53/53 checks passed` | **仅对 `.cs` 走“构建能力拒绝”路径的部分**与本批口径相关；本脚本对该路径只断言“拒绝 + suggestion”，未断言 `valid`，故无需改期望 |
| `mcp053_added_tools_evidence.ps1`（追加） | 0 | `73/73 checks passed` | **期望按新口径更新后通过**：`a10`（批量混合）、`a18`（两工具一致）、`a19`（不得发布 `valid:false`）三处由 `valid -eq $false` 改为 `$null -eq $valid` + `reason` 断言。`a20`（工具零写入）仍 PASS（前一轮 TASK-055 的 1.5 s settle 已保留） |

**期望更新为什么是合法的、不是“改测试掩盖缺陷”**：这与 TASK-054→TASK-055 更新同一族期望是同一处置——
被修正的是**实现不符合契约描述**（§1.5），期望跟着**契约**走；且 `mcp053` 的 `a19` 名字本就是
“no valid false is ever published for the cs file”，更新后它才真正断言了这件事。
`mcp054_forensics_and_csharp_evidence.ps1` 的 `.cs` 断言只用 `category` + `suggestion`（`a06`），**无需改**，故未重跑（不在任务书清单内，且其断言面已被 `mcp053` 与 `mcp055` 覆盖）。
`mcp055_csharp_compile_verdict_evidence.ps1` 的同一处期望也已同步（`plain_plural_cs_is_language_unavailable`）；该脚本的 mono 相位是 TASK-055 的 pre/post 对照主体，**本批未重跑它**（其被本批影响的唯一断言在 plain 相位，已由 §1.4 的逐字节对照与 `mcp053` 独立覆盖）。

**回归副作用的还原**：回归会重写已跟踪的 `docs/reports/evidence/task050/red/**`、`task051/red/**`、`task053/**`
（以及新增未跟踪的 `task051/red/e20_child_status.json`），已按 TASK-055 同一处置 `git checkout HEAD -- …` 还原并删除新文件；
收尾 `git status --porcelain` 只剩本批的 10 个已改文件 + `docs/reports/evidence/task056/**` + 4 个新增脚本 + 4 个既有未跟踪物。

---

## 8. 偏离、风险、未覆盖

### 8.1 与任务书的显式偏离

1. **D2 写 `v1.17.0` 而非 `1.16.0`**（§2）：任务书写于审计时点，TASK-055 已将生成器升到 1.17.0；写 1.16.0 会立即造成同样的漂移。
2. **回归清单追加 `mcp053`**（任务书 §4 未列）：它的三处期望被 D1 影响，若只改不跑就是“改了期望但没证据”，故一并跑（73/73）。
3. **未重跑 `mcp054` / `mcp055` 证据脚本**（任务书未列；见 §7 末段的覆盖论证）。`mcp055` 的期望已同步更新，但它的 mono 相位未重跑。
4. **D1 未改契约描述**（§1.5，含逐字引文与 sha 未变的证据）。

### 8.2 风险 / 已知边界（交给决策者）

| ID | 风险 | 依据 |
|---|---|---|
| R1 | `language_unavailable` 的 `reason` 是**本批新增的线上字段**：只读 `valid` 的老客户端不受影响（仍是 null），但把批次条目的键集合当 schema 校验的调用方会看到新键。契约描述写的是“类别 + 计数 + valid 只给 ok/invalid”，没有承诺键集合固定 —— 属**信息增加**，非破坏 | §1.4；`REPORT-055` §6 的 `not_compiled_count` 同一类先例 |
| R2 | D3 的规范化把**整条目录**的分隔符统一到平台原生形态；`PATH` 里写成前斜杠的 Windows 项会被改写成反斜杠后再 `FileAccess::exists()` 与 `CreateProcessW`。两者都是 Windows 文件系统 API，实测 exit 0 且产物存在 | §3.4；`csharp_executable_path` 的 12 条 doctest |
| R3 | `accept_m1` / `check_contract_subset.ps1` 仍含既有非 ASCII 字节（22 / 12 个），与本批无关（本批 `scripts/mcp056_*.ps1` 三个新脚本**纯 ASCII**，实测非 ASCII 字节 = 0） | `[IO.File]::ReadAllBytes` 逐字节统计 |
| R4 | 门⑥ 的保证仍是**有界拼写集合**（`--coverage` 自陈）；本批未新增收窄点，但这是机器保证的边界 | §6 |
| R5 | `command` 字段仍**不给可执行文件加引号**（含空格的路径在字段里没有引号），只影响“可读性/可粘贴”，不影响执行（argv 分传） | §3.2；本批未扩大范围 |

### 8.3 不可构造 / 未覆盖（显式声明）

* **“修前二进制”本身**：`bin/` 不受版本控制且已被重建覆盖 → 修前对照改用**仓库内已跟踪的 TASK-055 记录**（§1.4），
  并对第三方审计记录做 sha256 复核；没有编造“我跑过旧二进制”。
* `language_unavailable` 里“进程根本没有初始化任何脚本语言"的子形态（`--test` 进程走的是 `STRUCTURAL` 回退，见 `classify_validate_script_mode`）：
  其 `reason` 文案由同一函数产出，线上证据覆盖的是“语言未注册”这一支（`.cs` / `.gdshader`）。
* 非 Windows / 非中文 MSBuild 形态、超时杀子进程的孙进程边界：与 TASK-055 相同，未见变化，不在本批范围。

---

## 9. 证据清单（关键文件与 sha256）

| 文件 | sha256 / 说明 |
|---|---|
| `docs/tools_list.renamed.json` | `9c70605436a5b559eb973434d9cda6d6a9e0c6bef9ec3318d409137f2ba288f5`（**未动**；== 生成器输出） |
| `docs/tool-groups-added.json` | `fb15a9f43861f080ed9f4c29d98bd85f62f48ca03e503e57011fcc0cace4fcd3`（D2 一行；TASK-055 为 `0735fe29…`） |
| `evidence/task056/plain-91-plural-cs.response.json` | `48d2ef13d75f1976a0bcfcc6a0ff62dd9be57ac2b7024b2e942d7072903d7371`（1369 B） |
| `evidence/task056/plain-90-singular-cs.response.json` | `62c37e40eaee6f53a95e204030777cfbc8148a90180ec9ecf17de4a4c65b3136`（455 B，与 TASK-055 同值） |
| `evidence/task056/mono-build-csharp.response.json` | `a1010292b6918eea18e88f7cf85dfc6205ac9fe0d4641af2d0d9d0320bedaa84`（1505 B；`command` 与 `exit_code` 见 §3.4） |
| `evidence/task056/pre_post_compare.log` | `PRE_POST_COMPARE=PASS`（D1 + D3 全部条目） |
| `evidence/task056/summary-plain.txt` / `summary-mono.txt` | `plain: 13/13` / `mono: 11/11`；各自含 9877 guard PASS 证据（`summary.txt` = 最后一次运行，即 mono） |
| `evidence/task056/gates/{9 个 .log,summary.txt}` | 9 步全 exit 0 |
| `evidence/task056/regression/{15 个 .log,summary.txt,accept_m1_pass_list_compare.txt}` | 15/15 exit 0；PASS 清单 differ=0 |
| 生成器自报（`%TEMP%\mcp056\gen1.log`） | `input tools = 174 / output tools = 175 / added = 4 / overrides = 29 / output sha256 = 9c706054…` |

---

## 10. 复跑入口

```powershell
# 1) 构建（串行！）
cmd /c modules\mcp_server\scripts\build_local.cmd -Force
# 2) D1/D3 线上证据（plain 相位 + mono 相位；mono 二进制须先由 scons 构建）
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp056_evidence.ps1 -Phase plain
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp056_evidence.ps1 -Phase mono
python modules\mcp_server\scripts\mcp056_pre_post_compare.py
# 3) 门
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp056_gates.ps1
# 4) 回归（含 accept_m1 ×2；跑完按 TASK-055 先例还原被重写的 evidence 目录）
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp056_regression_battery.ps1
git checkout HEAD -- modules/mcp_server/docs/reports/evidence/task050/red modules/mcp_server/docs/reports/evidence/task051/red modules/mcp_server/docs/reports/evidence/task053
```

## 11. 交接

* **二进制**：plain `bin\godot.windows.editor.x86_64.console.exe` = `4.8.dev.custom_build.4e3de1090`；
  mono `bin\godot.windows.editor.x86_64.mono.console.exe` = `4.8.dev.mono.custom_build.4e3de1090`（均构建自本批工作树）。
* **锚点**：工作树/构建点 = HEAD **`4e3de109037ffa5d17b1d08f9df2876810bb656b`**；
  本批改动落成**实现提交 `75adcdcce89fb55a4d319d0ff8bd5db8bd456536`**（29 files changed, 934 insertions(+), 36 deletions(-)；
  含 4 个新脚本、`evidence/task056/**` 与全部跟踪代码/测试改动），本报告由紧随其后的提交落盘。**未 push**。
* **建议下一步**：由**全新的独立验收子代理**重跑 `REPORT-AUDIT-ADDED` §2/§3.3/§6（对等门 + 两个校验工具 + 门），
  并复核本批的 `valid: null` 口径、D2 的版本串、D3 的 `command` 逐字节对照；U1（`editor_set_node_script_batch` 取回腿线上不可达）
  与 R1（孙进程）沿用原报告的登记。
