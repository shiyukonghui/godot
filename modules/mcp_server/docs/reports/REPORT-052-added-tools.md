# REPORT-052 — C 档 1：契约扩张机制 + 两个新增工具（`project_build_csharp` / `project_write_text_file`）

> 任务书：`docs/tasks/TASK-052-added-tools.md`；手册：`docs/tasks/PLAYBOOK-group-port.md`；
> 规范：`DESIGN-DETAIL.md` **§26/GDR-28**（契约扩张）。证据来源：`docs/reports/REPORT-AUDIT-RACING-BACKLOG.md`（M-2/N-3）。
> 执行者只写**报告**；决策日志按 PLAYBOOK §0 属于 harness 仓库 `F:\moonbit-hof-rs\DECISIONS.md`（本 fork **只读**），
> 因此本文件的 §7「决策记录」是本批决策的可查载体，本 fork 内**没有**新建 `DECISIONS.md` 或竞争性规范文档。
>
> **本报告只允许改 `modules/mcp_server/**`**（已遵守）；hof-rs 全程只读（`tests/fixtures/mcp/tools_list.json` 只被生成器读取）；
> **没有改 `DESIGN-DETAIL.md` 与 `tool-rename-map.json`**；**没有占用/杀/重启 9877**；端口只用 9888/9889；**没有 push**。

---

## 0. 结论摘要（按 D86 标锚点）

| 项 | 结论 | 锚点 |
|---|---|---|
| §0 机制：`ADDED_TOOLS` + `_meta.added_tools/added_count` + 幂等 | **完成** | §1；契约 sha `1cb68de8…eee0` 连跑两次相同 |
| §0 机制：`171+N = 66+105+N`，新增恰好一次（missing/foreign/duplicated=0） | **完成** | §1.4；`--check-completeness` exit 0，打印 `171 + 2 = 66 + 105 + 2` |
| §0 机制：`docs/tool-groups-added.json` + `--added`（不改既有批次清单） | **完成** | §1.3；`--added` exit 0（3467 B，sha `bad332b7…0de7`） |
| §0 机制：结构化 diff（只动新增条目 + `_meta`）+ 不可手改契约 | **完成** | §1.5；`mcp052_contract_diff.py` 34 checks / 0 problems |
| §1.1 `project_build_csharp` 全部行为要求 | **完成**（能力缺失诚实拒绝、失败不伪造 0、超时真杀子进程） | §2.1、§3.2、§5.2–§5.4 |
| §1.2 `project_write_text_file` 全部行为要求 | **完成**（四类拒绝 + 无删除路径 + 不静默覆盖 + 读回核实 + 原子发布） | §2.2、§5.1 |
| §1.2 闭环：**从零只用工具**建 C# 工程并构建成功 | **完成** | §5.5；`c5` exit_code=0，dll 4096 B sha `707db412…e9110` |
| 门①（171 移植逐字 + N 新增逐字，9888/9889） | **PASS** 3/3 ×2 组 | §4.1 |
| 门②（三类证据 + 跨工具闭环） | **PASS** 53/53（exit 0） | §4.2、§5 |
| 门③（模块 doctest） | **PASS** 315/315 用例、22935/22935 断言 | §4.3 |
| 门④（全引擎回归） | **PASS** 1741/1741 用例、447217/447217 断言、0 failed | §4.4 |
| 门⑤（`accept_m1.ps1` 连跑两次） | **PASS** 22/22 ×2，PASS 清单一致 | §4.5 |
| 门⑥（三段式） | **PASS** exit 0 / exit 0 / 101 探针全过 | §4.6 |
| TDD 红→绿 | 红 47/97 断言失败（工具缺失）→ 绿 8/8、199/199 | §3 |
| 构建绑定 HEAD | 两个二进制都自报 `f38d240ab` == HEAD | §4.0 |
| 规范缺口（必须由决策者裁定） | 3 项：闭集动词归属、`-32001` 与 GDR-14 语义冲突、`timeout_ms` 与框架上限关系 | §7、§8 |

---

## 1. §0 机制：契约扩张（GDR-28 逐条落地）

### 1.1 生成器：`ADDED_TOOLS`（**与两张 override 表分离**）

`scripts/gen_renamed_contract.py` v1.13.0 → **v1.14.0**，新增第三张表 `ADDED_TOOLS`（列表，不是按 `old_name` 索引的字典——
新增条目**没有** `old_name`，这正是「新增」与「override」的分界）。它与 `DESCRIPTION_OVERRIDES`/`SCHEMA_OVERRIDES`
**并列而分离**，在**重命名 + override 之后确定性追加**；每条新增记录只输出契约的三个字段
（`description` / `inputSchema` / `name`，与移植条目同键序），外加一条**不进入契约**的 `reason`（为什么存在，见 §5 的
report 引用与生成器运行输出）。

生成器新增的自检（任一失败即 `sys.exit`，不产出文件）：

* `validate_added()` 对新增名做 **GDR-16 同规 lint**：L1 正则 + L4 无 `update_` + L2 动词合法 + L3 `channel`/`verb`
  与「从名字解析出来的」一致（新增条目没有 map 行，所以这两项与记录自己的声明交叉验证，而不是与 map 交叉验证）；
* 新增名 **不得**与 171 个移植名、以及 map 的 174 个 `new_name` 相撞；表内不得重名；
* `ADDED_VERB_EXTENSIONS` 里的记录**必须被用到**（陈旧记录 = 失败），见 §7.1。

### 1.2 `_meta`：`added_tools` + `added_count`

```json
"tool_count_in": 174, "count": 173,
"added_count": 2, "added_tools": ["project_build_csharp", "project_write_text_file"],
"order_normative": false, …
```

`_meta.count` 仍是 `len(result.tools)`（= `171 + N`），`added_tools` 的顺序就是追加顺序，且这两个名字**就是**
`result.tools` 的末两条（`mcp052_contract_diff.py` 的 `added_entries_are_the_tail` 把「追加发生在 rename+override
之后」变成机器断言，而不只是注释里的承诺）。

### 1.3 `docs/tool-groups-added.json`（**不改**任何既有批次清单）

新增工具自己的组清单，受**与移植批次同样的组规则**约束：单渠道 / 单作用域 / 单 `mutating` / 组 ≤10 /
`implemented` 布尔 / 每组一条 `notes`；两处**移植批次没有**要求：

1. 组必须**声明 `verb`**（新增条目没有 map 行），`--added` 把「名字派生的 verb」与声明比对；
2. 它的并集必须**双向等于** `_meta.added_tools` —— 生成器表与清单不能各自漂移。

```
GROUP   project_csharp_build   channel=project scope=both mutating=True implemented=True verb=build tools=1
GROUP   project_text_write     channel=project scope=both mutating=True implemented=True verb=write tools=1
ASSERT  manifest = contract _meta.added_tools, both directions: PASS (missing=0, foreign=0)
ASSERT  every added tool appears exactly once: PASS (duplicates=0)
ASSERT  every name exists in the 173 entry contract: PASS
ASSERT  every group is one channel + one scope + one mutating value: PASS
ASSERT  channel and verb derived from every tool name agree with the group declaration: PASS
ASSERT  every added verb is in the closed set or has a used verb_extensions record: PASS
BYTES 3467
SHA256 bad332b7ab1b6c48f46228888631f95761c642c78ccf35f78a63e2256dbf0de7
TOOL-GROUPS-ADDED CHECK PASS
```

`scope = both` 的判据（任务书要求「按映射口径复核后定，并在报告说明」）：`tool-rename-map.json` 里 **project 渠道的每一条**
`scope` 都是 `both`（`project_set_setting`、`project_create_script`、`project_edit_script`、`project_create_theme` …），
而这两个工具依赖的是「机器的 SDK」与「项目目录」，都不属于编辑器进程——所以沿用映射口径 = `both`。判据不是猜的：
证据脚本把 `tool-groups-added.json` 的 scope 与 map 合并后**派生**出两个端点的期望集合（150 / 71），并与实况比对。

### 1.4 `--check-completeness`：`171 + N = 66 + 105 + N`

从 `171 = 66 + 105` 变成四个**互不相交**的桶：B1/B2（66）+ B3/B4/B5（105）+ added（N），加上 `contract - added = 171`。
四个桶两两不相交被显式断言，所以这条恒等式成立时「每个名字恰好属于一个桶」成立：

```
SOURCE  contract entries                       = 173
SOURCE  implemented by the B1/B2 manifests    = 66
SOURCE  added tools (_meta.added_tools)       = 2 (project_build_csharp, project_write_text_file)
DERIVE  contract - implemented                 = 173 - 68 = 105
ASSERT  B3 + B4 + B5 = 40 + 7 + 58 = 105 tool(s), each exactly once: PASS
ASSERT  B3/B4/B5 disjoint from B1/B2 (66 tools) and the added manifest (2 tools): PASS
ASSERT  in_contract_and_not_implemented, both directions of the difference: PASS (missing=0, foreign=0)
ASSERT  171 + 2 = 66 + 105 + 2: PASS (contract = B1/B2 union + B3/B4/B5 union + added)
ASSERT  every one of the 173 contract names is in exactly one of the four buckets: PASS
TOOL-GROUPS-COMPLETENESS CHECK PASS
```

三份批次清单的字节与 sha256 在输出里照旧打印（B3 `d3422a6e…956a`、B4 `d95d7d9e…a708`、B5 `85bb783e…9fb`），ADDED 追加一行。

### 1.5 结构化 diff（GDR-28 第 7 条）与幂等

新增 `scripts/mcp052_contract_diff.py`（`mcp043/050/051_contract_diff.py` 的同族，**不放松**任何既有断言）：

```
[PASS] before_is_171 :: before entries = 171 (expected 171)
[PASS] after_is_173 :: after entries = 173 (expected 173 = 171 ported + 2 added)
[PASS] no_ported_tool_removed :: removed names = []
[PASS] difference_is_exactly_the_added_names :: added names = ['project_build_csharp', 'project_write_text_file']
[PASS] ported_entries_are_byte_identical :: ported entries that changed = [] (of 171 compared)
[PASS] meta_added_tools_is_the_declared_pair / meta_added_count_matches / added_entries_are_the_tail
[PASS] added_entry_fields_* :: 三个字段，无 old_name 残留
[PASS] meta_count_moved :: 171 -> 173      [PASS] meta_generator_version_moved :: 1.13.0 -> 1.14.0
[PASS] meta_unchanged_map_sha256 :: equal  [PASS] meta_unchanged_overrides :: equal   …（共 10 项）
[PASS] meta_has_no_unexpected_new_member / meta_has_no_dropped_member
checks = 34, problems = 0; wrote …\mcp052\contract-diff.json
```

**幂等**：`gen_renamed_contract.py` 连跑两次输出 sha 相同 —— `1cb68de8bdd58cd6038532af28cd34e73fb18d2c58eea9490c762dc0e515eee0`。
契约**只经生成器产生**，没有任何手改（契约文件在本批的 diff 完全由上面 34 条断言描述）。

### 1.6 谁读了第六份清单（对等门口径改变后的联动）

| 消费者 | 改动 |
|---|---|
| `scripts/check_contract_subset.ps1` | 读第六份清单；`implemented` 并集含新增组；**新增工具没有 map 行**，所以 `$scopeOf` 用 `tool-groups-added.json` 的组 `scope` 兜底（并把该 scope 端到端验证：scope 写错会让某端点期望集错误，从而计数/多余-缺失断言失败） |
| `scripts/accept_m1.ps1` | `-ManifestFileNames` 加 `tool-groups-added.json`；`Get-ToolScope` 同兜底；`$ExpectedContractSize` 从字面量 171 改成**派生** `171 + _meta.added_count`（并断言 `contract == 171 + added_count`） |
| `scripts/check_evidence_args.py` | `MANIFESTS` 加第六份，使注册块普查覆盖新增工具 |
| `docs/scripts/check_tool_groups.py` | 新增 `--added`；`--check-completeness` 改四桶恒等式；用法串同步 |

---

## 2. 两个新增工具

### 2.1 `project_build_csharp`

* **通道/动作/作用域**：`project` + `build` + `csharp`，`scope=both`、`mutating=true`（GDR-18 保守口径：构建会在项目里写
  `bin/`、`obj/`，默认 rescan 也会碰编辑器缓存）。
* **契约条目逐字**（生成器 `ADDED_TOOLS`，与 `tools_list.renamed.json` 同源）：
  description 见 §4.1 的 `description=True`；`inputSchema` = `timeout_ms`(integer, 1000..600000, 默认 120000) /
  `configuration`(enum Debug|Release, 默认 Debug) / `extra_args`(array of string, 默认 []) / `rescan`(bool, 默认 true)。
* **跨进程**：`OS::execute_with_pipe(path, args, false)`（`core/os/os.h:216`；Windows 实现
  `platform/windows/os_windows.cpp:1284-1409` 返回 `{"stdio": <out pipe>, "stderr": <err pipe>, "pid": <int>}`，
  两根管道都按 `PIPE_NOWAIT` 打开，见 `drivers/windows/file_access_windows_pipe.cpp:48-52`）。**不用** `OS::execute()`：
  它阻塞调用者且不可中断，无法满足「超时真的杀子进程」。
* **不阻塞主线程（GDR-20）**：`pending_handler` → `MCPDeferred::Task`，`tick()` 只做「读管道 + 查进程状态」，
  每个 `.csproj` 一个 `dotnet build`，按序执行。
* **超时真的杀子进程**：`get_timeout_ms()` 声明调用者的 `timeout_ms`，而框架只会**缩短**它
  （`mcp_jsonrpc.cpp:245-253`），并且框架的到期判定发生在 `tick()` **之前**（`mcp_deferred.cpp:126-137`）。因此
  task 自己算 `effective = min(requested, MCPPendingTimeout::effective_ms(服务器设置))`，在 `effective - 400ms` 自查到期 →
  **`OS::kill(pid)`** → 如实回答 `timed_out:true`、`exit_code:-1`（`OS::kill` 会把进程从引擎表里移除，退出码已不可读，
  所以 -1 是诚实的「不可知」而不是 0）、`killed:true`。析构函数另有一次 `kill()` 作为兜底（连接断开、框架到期、停机）。
* **stdout/stderr**：非阻塞排空，每流每工程 64 KiB 上限，截断由 `stdout_truncated`/`stderr_truncated` **标明**；解码是
  宽松 UTF-8（非法字节 → `?` 并计数），因为 `String::utf8()` 遇到第一个坏字节就截断整段（`ustring.h:556-560` →
  `append_utf8`），本地代码页的构建日志会被吃掉大半。
* **返回**：`exit_code` / `stdout` / `stderr` / `duration_ms` / `command`（真实命令行）/ `project_files` /
  `rescanned`，另加 `commands`、`exit_codes`、`timed_out`、`killed`、`stdout_truncated`、`stderr_truncated`、
  `non_utf8_bytes`、`timeout_ms`、`effective_timeout_ms`。**失败绝不伪造成 `exit_code:0`**：任一工程非零 → 汇总非零；
  被杀 → -1 + `timed_out:true`。
* **`.csproj` 定位**：从 `res://` 递归，跳过隐藏目录（`.godot`/`.git`）、`bin`、`obj`（MSBuild 输出），结果排序（确定性）。
* **capability-aware（GDR-28 第 6 条）**：①「本引擎构建有 C# 支持」用引擎自己的事实判断
  （`ScriptServer::get_language_count()`/`get_language(i)->get_name() == "C#"`，`core/object/script_language.h:79-80`；
  `CSharpLanguage::get_name()` 见 `modules/mono/csharp_script.cpp:90-92`），缺失 → `-32000` + 装法建议；②`PATH` 上找不到
  `dotnet`（`OS::get_environment("PATH")` + `FileAccess::exists`，Windows 先试 `dotnet.exe`）→ `-32000` + 装法建议；
  ③没有 `.csproj` → `-32001` + 建议 `project_write_text_file`。

### 2.2 `project_write_text_file`

* **拒绝**（全部 `-32602` + `data.suggestion` 点名该用哪个工具）：
  * `project.godot`（大小写不敏感）→ 指向 `project_set_setting`（引擎自己的 `ProjectSettings::save_custom()` 发布路径）；
  * `.tscn` → `project_create_scene_file`；`.tres` → `project_create_resource`/`project_edit_resource`；
    `.gd` → `project_create_script`/`project_edit_script`；`.cs` → 同上（`project_create_script` 本来就收 `.gd`/`.cs`，
    `project_script_write.cpp:109-126`）；
  * `res://` 之外（`user://`、`C:/…`）与任何 `..` 段（`normalize_project_path`，与 `normalize_screenshot_path` 同族）；
  * 只给目录不给文件（`res://`、`res://dir/`、全空白）——`trace` 里这个点被自己的 doctest 抓出来过，见 §3。
* **没有任何删除路径**：schema 恰三个成员（`content`/`overwrite`/`path`），没打开过删除；`overwrite:false` + 已存在 →
  **拒绝**，**不静默覆盖**，且响应之后**文件字节未变**（证据里前后 sha 相同）。
* **写后读回核实**：发布后把文件读回来与请求内容逐字节比对（不等 → `-32603`），返回的 `bytes`/`sha256` 描述的是
  **磁盘上的文件**（`bytes` = UTF-8 字节数，`sha256` = `FileAccess::get_sha256()`）。
* **原子发布**：复用 `publish_text_atomically` → `publish_file_atomically`（`tools/tool_helpers.cpp:488-554`）：
  先写同目录 `*.mcp-tmp.*` 兄弟文件、确认临时文件真的存在、再 rename 覆盖目标；失败时把旧字节从 `.bak` 放回。
  「原子」的依据就是这条既有语义，本工具**没有**自己实现第二份发布逻辑。

### 2.3 命名与注册面

* 注册在 `tools/registration.cpp` 末尾两行（各一行 include + 一行调用），文件各一（`tools/project_csharp_build.*`、
  `tools/project_text_write.*`），符合「一批只有一个实现者在改树」。
* **注册器的闭集动词**：注册时 `MCPToolRegistry::validate_tool_name()` 会做 GDR-16 L2 检查，而 map 的 37 动词闭集里
  **没有** `build`/`write`。因此 `tool_registry.cpp` 新增**第二个**列表 `MCP_ADDED_TOOL_VERBS = {"build","write"}`：
  37 词列表**逐字不动**（它仍是 map 的闭集），新增动词只能经这条显式记录进入。决策与三个记录的一致性见 §7.1。
* **schema 以 C++ Dictionary 构造**（不是 JSON 文本 parse）：`JSON::parse` 把每个 JSON 数字都变成 FLOAT，
  `JSON::stringify` 会把整数 float 写成 `1000.0`，而契约写的是 `1000` —— 门①逐字段比较 live 与契约，**第一次跑就是红的**
  （`inputSchema=False`）。这是本批唯一一个由门①抓出来、doctest 抓不到的缺陷（doctest 两侧都过 JSON 往返），
  修完之后另加了「三个数字必须是 INT Variant」的 doctest 防回归。

---

## 3. TDD 红 → 绿

用例先写、先跑（此时两个工具尚未存在），全部走**注册表**（红是「工具缺失」而不是「断言写错」）。

**红（`--test-case="*TASK-052*"`，exit 1）**

```
[doctest] test cases:  4 |  0 passed |  4 failed | 1737 skipped
[doctest] assertions: 97 | 50 passed | 47 failed |
[doctest] Status: FAILURE!
.\modules/mcp_server/tests/test_mcp_server.h(25050): FATAL ERROR: REQUIRE( entry.has("inputSchema") ) …
.\modules/mcp_server/tests/test_mcp_server.h(25039): FATAL ERROR: test case CRASHED: Unhandled SEH exception caught
```

红跑里出现的两次**用例崩溃**本身是两个真实教训，已按 PLAYBOOK §7.6 修好（REQUIRE 不中止用例 → 它之后的每次索引都要自己守卫）：
`entry["inputSchema"]` 在空字典上取不到键、`properties[0]` 在空数组上越界。

**绿（同一条过滤，exit 0）**

```
[doctest] test cases:   8 |   8 passed | 0 failed | 1736 skipped
[doctest] assertions: 199 | 199 passed | 0 failed | 0 failed
[doctest] Status: SUCCESS!
```

八个用例：① 两个端点都注册、描述/schema 逐字、INT 边界类型；② 四类家族 + `project.godot` + 路径拒绝 + 缺参；
③ 写入/读回/覆盖规则；④ 无删除路径；⑤ 构建参数规则（先于能力检查）；⑥ 能力探针与超时生效值；
⑦ `.csproj` 搜索与命令行规则；⑧ 真实子进程「启动 → 排空 → 真的被杀」。

⑧ 是 §1.1 ④「证明子进程被杀」的 engine 侧证据：`cmd.exe /c ping -n 30 127.0.0.1` 启动后 `kill()`，
`is_process_running()` 立刻为假、`kill_called()` 真、`exit_code()==-1`；同一个用例还证明快速子进程的 stdout 被捕获
（`echo mcp052-hello`）、以及 256 字节上限真的截断且被 `stdout_truncated()` 标明。

---

## 4. 门（真实输出 + 退出码）

### 4.0 构建绑定 HEAD（R-1）

* 非 mono：`cmd /c "modules\mcp_server\scripts\build_local.cmd -Force"`（tests=yes，**从 cmd 启动**，不抑制输出）→
  `build_local: exit code = 0`；`git rev-parse --short HEAD = f38d240ab`，
  `bin\godot.windows.editor.x86_64.console.exe --version = 4.8.dev.custom_build.f38d240ab` ✔
* mono（**串行**重建，与上面不并发）：
  `cmd /c "D:\Anaconda\Scripts\scons.exe platform=windows target=editor module_mono_enabled=yes tests=yes -j8"` →
  `scons: done building targets.` / `Info: Time elapsed: 00:01:37.65` / exit 0；
  `…mono.console.exe --version = 4.8.dev.mono.custom_build.f38d240ab` ✔
* 两个二进制自报的 hash 都等于 **`f38d240ab`**，即「包含全部编译期改动的提交」。

### 4.1 门① 契约子集逐字（对等门口径 = 171 移植逐字 + N 新增逐字）

`powershell -NoProfile -ExecutionPolicy Bypass -File scripts\check_contract_subset.ps1 -Group project_csharp_build` → **exit 0**

```
[PASS] editor_9888_contract_subset   editor port=9888 tools=150 … | project_build_csharp: name=True description=True inputSchema=True
[PASS] game_9889_contract_subset     game port=9889 tools=71  … | project_build_csharp: name=True description=True inputSchema=True
[PASS] guard_user_port_9877          pid_before=-1 pid_after=-1
group=project_csharp_build tools=1 contract=173
implemented_union=150 tools (editor endpoint) / 71 tools (game endpoint)
3/3 checks passed
```

`… -Group project_text_write` → **exit 0**，同样 3/3：`project_write_text_file: name=True description=True inputSchema=True`
（两个端点各一遍）。**未实现却已注册**、**已实现却缺失**、**多余工具**仍会失败——强度未放松，只是并集多了第六份清单。

### 4.2 门② 三类证据 + 跨工具闭环

`powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp052_added_tools_evidence.ps1` → **exit 0**，
`53/53 checks passed`，证据目录 `%TEMP%\mcp052\evidence`，日志 sha256
`6142dd91…23666`（第二跑；每次请求/响应都留 `.request.json`/`.response.json` 并打印 bytes + sha256）。逐条见 §5。

### 4.3 门③ 模块 doctest

```
bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="[MCPServer]*"   → exit 0
[doctest] test cases:   315 |   315 passed | 0 failed | 1429 skipped
[doctest] assertions: 22935 | 22935 passed | 0 failed |
```

基线 = 307 用例（315 − 本批 8），只增不减；全绿。

### 4.4 门④ 全引擎回归

```
bin\godot.windows.editor.x86_64.console.exe --headless --test  → exit 0
[doctest] test cases:   1741 |   1741 passed | 0 failed | 3 skipped
[doctest] assertions: 447217 | 447217 passed | 0 failed |
```

### 4.5 门⑤ `accept_m1.ps1` 连跑两次

```
run1: 22/22 cases passed ; implemented tools = 150 (editor) / 71 (game); contract = 173; guard_user_port_9877 PASS
run2: 22/22 cases passed ; 同上
PASS 清单比较: PASS LISTS IDENTICAL (22 entries)   （两次都含 gate_scope_declared PASS）
```

`gate_scope_declared` 现在校验的是派生值 `contract == 171 + _meta.added_count`（`expected_contract=173`）。

### 4.6 门⑥ 收窄点三段式（GDR-24 / §22.3b 规则 4）

```
python scripts\check_narrowing_points.py            → exit 0
  scanned     : 75 narrowing point(s) in 16 file(s)
  pinned      : 75
  coverage    : 17 declared spelling(s)
python scripts\check_narrowing_points.py --coverage → exit 0
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp031_gate6_coverage_probes.ps1 → exit 0
  101/101 checks passed; … B1b_restored_is_green / B1b_restored_scanned_75 / B1b_restored_byte_identical
```

**新收窄点 = 0**：本批新增的 `tools/project_csharp_build.cpp|h`、`tools/project_text_write.cpp|h` 一个都没落在
17 种已声明拼写内（新增代码只做整数类型转换：`(int64_t)`、`(uint8_t)`、`(char32_t)`、`(ProcessID)`，
整数收窄自 TASK-023 起明确在门⑥ 之外——见 `NOT_COVERED` 第 3 条）。`scanned == pinned`、0 误报、探针后字节还原。

---

## 5. 门② 的三类证据与闭环（逐条）

三类证据（任务书 §1.1/§1.2 各四条要求）对应到检查项：

### 5.1 `project_write_text_file`：成功 / 缺参 / 底层拒绝

| 类 | 检查项 | 实测 |
|---|---|---|
| 成功 | `a14_write_success_matches_the_file_on_disk` | `path=res://Mcp052Loop.csproj created=True`，回答的 sha256 == 磁盘 `Get-FileHash` |
| 成功 | `a15_second_write_is_honest_too` | `NuGet.config` 同上 |
| 成功 | `c12_cfg_written_for_the_readback` + `c13_another_tool_reads_what_the_writer_wrote` | 写 `.cfg` 后由 **另一个工具** `project_search_file_contents` 读回命中 ≥1 行（**零字符串手术链**；该读者的文本扩展白名单不含 `csproj`/`config`，见 §7.6） |
| 缺参 | `a12_missing_path_is_32602` / `a13_missing_content_is_32602` | `-32602 Missing required parameter: path / content` |
| 本文之外的路径 | `a5..a11` | `project.godot`→`project_set_setting`；`.tscn`→`project_create_scene_file`；`.tres`→`project_create_resource`；`.gd`/`.cs`→`project_create_script`；`user://`、`res://..` →`-32602` + 建议 |
| 状态拒绝 | `a16_occupied_destination_…` | `-32001`，建议含 `overwrite`，**文件 sha 前后相同**（未静默覆盖） |
| 无删除路径 | `a17_delete_shaped_argument_is_refused` | `{"remove":true}` → `-32602 Unknown parameter`（注册表未知参数门；不是「静默忽略」） |
| 无删除路径 | `a18_schema_has_exactly_three_members` | `properties = [content, overwrite, path]`（活体 `tools/list` 上读的，不是源码印象） |

### 5.2 `project_build_csharp`：参数 / 能力 / 失败 / 超时

| 类 | 检查项 | 实测 |
|---|---|---|
| 参数（先于能力） | `a19`–`a22` | `configuration="Fast"`→`-32602`；`timeout_ms=500`→`-32602`；`extra_args=7`→`-32602`；`rescan="yes"`→`-32602` |
| 能力缺失（无 C# 支持，**诚实拒绝**） | `a23_plain_engine_refuses_without_csharp_support` | 非 mono 编辑器：`-32000`，message 说明无 C# 支持，`suggestion` 说怎么装（`module_mono_enabled`） |
| 底层缺失（有 C# 支持但还没有工程文件） | `b1_no_csproj_is_32001_with_a_suggestion` | mono 编辑器：`-32001 A '.csproj' file below 'res://' not found` + 建议 `project_write_text_file` |
| 成功 | `c5_closed_loop_build_succeeded` | `exit_code=0 timed_out=False duration_ms=2505 command='"C:\Program Files\dotnet\/dotnet.exe" build …\Mcp052Loop.csproj -c Debug' project_files=[res://Mcp052Loop.csproj] dll=True (4096 B, sha256=707db4120a6ed6211aa1ca47d97ab9604a600f199957c5b0dd070b9b166e9110)` |
| 输出捕获 | `c5b_stdout_carries_the_sdk_output` | `stdout > 0`、`stdout_truncated=false` |
| **失败不伪造 0** | `c7_broken_build_is_a_nonzero_exit_code` | 故意写错的 `.cs`：`exit_code=1 timed_out=False stdout_bytes=1729 mentions_error=True` |
| **超时真杀子进程** | `c10_timeout_reports_timed_out_and_a_kill` | 一个会挂住 ~11 s 的 MSBuild target + `timeout_ms=2000`：`timed_out=True exit_code=-1 killed=True duration_ms=1600 timeout_ms=2000 effective_timeout_ms=2000`（1600 = 2000 − 400 的自查期，正是设计值） |
| **子进程真的死了** | `c11_the_build_child_really_died` | 调用前后 `Get-Process dotnet` 的 pid 集合：`new=[]`（另加 `/nodeReuse:false`），有界重试 4×500 ms |

### 5.3 `project_build_csharp` 的协议面

| 检查项 | 实测 |
|---|---|
| `a2_editor_serves_both_added_tools` / `a3_editor_live_count_is_the_contract_view` | 编辑器 9888 同时服务两个新增工具；`live=150` == 派生期望 150 |
| `a4_*_verbatim_on_the_editor` ×2 | `description=True inputSchema=True`（与契约逐字） |
| `d2_game_serves_both_added_tools` / `d2b_game_live_count_is_the_contract_view` | 游戏 9889（mono）：服务两个新增工具；`live=71` == 派生期望 71（`scope=both` 的端到端证明） |
| `d3_*_verbatim_on_the_game` ×2 | 逐字 True ×2 |
| `endpoint_expectations_derived` | 150/71 是**派生**出来的（map scope + 新增清单 scope 合并），不是写死的数字 |
| `port_9877_guard` | `listening=False pid_before=-1 pid_after=-1`：本脚本从未占用/杀/重启用户的 9877，且所有它启动的命令行都进了 guard（含两次 `--import`） |

### 5.4 闭环全过程（「从零、只用工具」逐步响应 + sha256）

每一步的请求/响应文件都在 `%TEMP%\mcp052\evidence`，`c*.response.json` 的 sha256 记在 `evidence.log.txt`
与 `results.json` 里；下面给的是**当次实况**摘要（逐步）：

| 步 | 工具 | 结果 |
|---|---|---|
| c1 | `project_set_setting` {key=application/config/name, value=Mcp052ClosedLoop} | `value=Mcp052ClosedLoop saved=true`（工程名由工具写入，非手改 `project.godot`） |
| c2 | `project_write_text_file` `res://Mcp052Loop.csproj` | `created=true`，回答 sha256 == 磁盘 sha256 |
| c3 | `project_write_text_file` `res://NuGet.config` | 同上 |
| c4 | `project_create_script` `res://Mcp052Loop.cs`（content = 合法 C#，`template=Node`） | `path/bytes` 正常，文件在磁盘上 |
| c5 | `project_build_csharp` {configuration=Debug} | `exit_code=0`，产出 `bin/Debug/net8.0/Mcp052Loop.dll`（4096 B，sha256 `707db412…e9110`） |
| c7 | 写坏 `.cs` 后 `project_build_csharp` | `exit_code=1`（失败没有被伪造成成功） |
| c10 | 写「会挂住」的 `.csproj` 后 `project_build_csharp` {timeout_ms=2000, extra_args=["/nodeReuse:false"]} | `timed_out=true, exit_code=-1, killed=true, duration_ms=1600` |
| c13 | `project_search_file_contents`（另一个工具）读回 `mcp052-readback.cfg` | 命中 ≥1 行 |

---

## 6. 回归与逐条归因

> 本节的脚本清单来自任务书「回归 `mcp041/042/043` + `mcp010/019/027` + `mcp044/045/046` + TASK-050/051 证据脚本」。
> 每个失败的**归因**写在下面（若全绿则写全绿）；**没有任何一条被「顺手改断言」掩盖**，凡因契约从 171 → 173
> 而必须调整的期望值，都在 §6.3 逐条列出。

### 6.1 已跑（退出码为准）

| 脚本 | 退出码 | 归因 |
|---|---|---|
| `mcp043_registration_literals.py` | 0 | 5 个工具的字面与契约相等（本批未触碰） |
| `mcp043_group_lookup.py` | 0 | 组查找仍能命中第五份清单；新增第六份不改变它的查询 |
| `mcp043_survey.py` | 0 | 抽样输出正常 |
| `mcp051_final_sweep.py` | 0 | `problems = 0 SWEEP OK`：生成 span 与源码一致（本批没动生成 span） |
| `check_evidence_args.py` | 0 | 普查：part A PROBLEM/MISSING=4、part B CANDIDATE=11，其中新增 1 条来自**本批证据脚本故意用未知参数 `remove`**（`mcp052_added_tools_evidence.ps1` 的 a17 探针）——它是**有意的**未知参数，属普查记录，不是缺陷 |
| `mcp052_contract_diff.py` | 0 | 见 §1.5（新增脚本） |
| `docs/scripts/check_tool_groups.py --added` / `--check-completeness` | 0 / 0 | 见 §1.3/§1.4 |
| `check_narrowing_points.py`（+`--coverage`）/ `mcp031_gate6_coverage_probes.ps1` | 0 / 0 / 0 | 见 §4.6 |
| `check_contract_subset.ps1`（两个新增组） | 0 / 0 | 见 §4.1 |
| `accept_m1.ps1` ×2 | 0 / 0 | 见 §4.5 |
| `mcp041_gates.ps1` / `mcp042_gates.ps1` / `mcp043_gates.ps1` | **0 / 0 / 0** | 见 §6.2 |
| `mcp051_gate1_groups.ps1` / `mcp050_regression_battery.ps1` / `mcp051_regression_battery.ps1` | **0 / 0 / 0** | 见 §6.2 |
| `mcp010_b2_observation_evidence.ps1` / `mcp019_b4_evidence.ps1` / `mcp027_object_shape_and_paths_evidence.ps1` | **0 / 0 / 0** | 见 §6.2（mcp010 改了 2 处期望来源） |
| `mcp044_capture_evidence.ps1` / `mcp045_pixel_compare_cost.ps1` / `mcp046_capture_encode_cost.ps1` | **0 / 0 / 0** | 见 §6.2 |
| `mcp047_m3_mono_check.ps1`（mono） | 0 | 11/11，见 §6.2 |

### 6.2 逐条归因（每个脚本：exit / 用时 / 自身汇总 / 归因）

| 脚本 | exit | 用时 | 自身汇总 | 归因 |
|---|---|---|---|---|
| `mcp041_gates.ps1` | 0 | 415 s | `DONE`（其内部子探针全部 EXIT 0） | 与契约规模无关（脚本不含 171/69/148 字样） |
| `mcp042_gates.ps1` | 0 | 432 s | `DONE`；末尾 `tree dirty after the run` 列出的是**本批尚未提交**的文件（含我改的 `mcp010_…ps1`），是提示不是失败 | 无关 |
| `mcp043_gates.ps1` | 0 | 517 s | `DONE`（含 `regress_probe037`/`regress_mcp040_probes`/`regress_mcp040_racing` 均 EXIT 0） | 无关 |
| `mcp051_gate1_groups.ps1` | 0 | 103 s | 五个 TASK-051 组各 `3/3 checks passed`（每组 editor/game 逐字） | 门① 的并集多了第六份清单后仍逐字通过 → **未放松** |
| `mcp050_regression_battery.ps1` | 0 | 138 s | `DONE` | 见下面的证据churn说明 |
| `mcp051_regression_battery.ps1` | 0 | 160 s | `DONE` | 同上 |
| `mcp010_b2_observation_evidence.ps1` | 0 | 35 s | 0 条 `[FAIL]`；`=== phase game: 29/29 checks passed ===` | **需要改期望值**：脚本的 `$ManifestFileNames` 只读五份批次清单、`$scopeOf` 只查 map，所以 171/148/69 的派生集会与 173/150/71 的实况冲突。已按 `check_contract_subset.ps1`/`accept_m1.ps1` 的同一口径改两处（加第六份清单 + 新增工具用其组的 `scope` 兜底），脚本结构未变、断言未放松 |
| `mcp019_b4_evidence.ps1` | 0 | 25 s | 全 `PASS`（含 `H1_user_editor_port_9877_guard`），无 `FAIL` | 无关 |
| `mcp027_object_shape_and_paths_evidence.ps1` | 0 | 24 s | `phase green: 60/60 checks passed` | 无关 |
| `mcp047_m3_mono_check.ps1`（mono） | 0 | 6 s | `11/11 checks passed`；其中 `m3e … tools/list under mono = 71 tool(s); expected 71 (the contract minus the scope=editor tools)` | **独立复现了 scope=both 的口径**：该脚本的期望值由契约派生，+2 自动流到 71，无需改脚本 |
| `mcp044_capture_evidence.ps1` | 0 | 59 s | `40/40 checks passed (phase editor)` | 无关 |
| `mcp045_pixel_compare_cost.ps1` | 0 | 30 s | `15/15 checks passed` | 无关 |
| `mcp046_capture_encode_cost.ps1` | 0 | 50 s | `23/23 checks passed` | 无关 |

**证据 churn（有意还原，非隐藏）**：`mcp050_regression_battery.ps1` 与 `mcp051_regression_battery.ps1` 会把
**它们自己的**证据就地重写进被跟踪的 `docs/reports/evidence/task050/**`、`task051/**`（15 个文件）。
那些文件是 TASK-050/051 报告的产物，记录的是**它们当时的 HEAD `889466b85`**（本次重跑会把 `git_head`、
`engine_version` 与 TASK-051 之后的参数提示文本一起换掉）。我**不**把别人的证据改写成 TASK-052 时代的副本：
跑完后 `git checkout -- modules/mcp_server/docs/reports/evidence` 还原为已提交字节，本次重跑的真实日志留在
`%TEMP%\mcp052_regression_mcp050_regression_battery.ps1.log` / `…mcp051_…log`（两者的 exit 0 与 `DONE` 见上表）。
这与 TASK-051 的做法一致（它把重跑副本放进**自己的** `task051/green/regression/task050-evidence-rerun/`，而不是覆盖原件）。

### 6.3 因「契约 171 → 173」而必须调整的期望值（逐条，全部有理由）

| 位置 | 改动 | 理由 |
|---|---|---|
| `tests/test_mcp_server.h`（15+22 处） | `get_tool_count()==69→71`、`get_visible_tool_count(false)==69→71`、`editor_registry.get_tool_count()==171→173`、`…(true)==148→150`、`…(true)==46→48`、`game_list/editor_list.size()` 同步 | 两个新增工具 `scope=both`，因此两个进程的表各 +2；断言是**绝对数字**（GDR-7 要求），不能用下界 |
| `tests/test_mcp_server.h` TASK-038 trace 用例 | fixture `list.tool_count = 171→173`（与其断言一起） | fixture 与该断言是「一次往返」的两侧，必须同值 |
| `scripts/accept_m1.ps1` | `$ExpectedContractSize` 171 → 派生 `171 + _meta.added_count` | 门⑤ 的 `gate_scope_declared` 比较的是契约大小；派生值避免下一个 N 又要手改 |
| `check_evidence_args.py` | `MANIFESTS` 加第六份 | 注册块普查要覆盖新增工具 |
| `scripts/mcp010_b2_observation_evidence.ps1` | `$ManifestFileNames` 加第六份；`$scopeOf` 加「新增工具取其组 scope」的兜底 | 该脚本按清单派生 171/148/69 的期望集，见 §6.2 |
| `docs/scripts/check_tool_groups.py` | `--check-completeness` 四桶化 + 新 `--added` | 任务书 §0.2/§0.3 |

**没有**改动的：`tool-rename-map.json`（map sha `2f552719…c2bd` 未变）、`tools_list.renamed.json` 的 171 条移植条目
（逐字相同，34 条断言里的 `ported_entries_are_byte_identical`）、既有五份批次清单（各自 sha 未变）、
`docs/scripts/*` 里被 explicit 声明为 frozen 的路径。

---

## 7. 决策记录（本批的「为什么长这样」；决策日志本体在 harness 仓库，本 fork 只读）

### 7.1 GDR-28 第 4 条没有说闭集动词是否约束新增名 —— 选「显式第二条列表」

* **触发**：`project_build_csharp`（verb `build`）与 `project_write_text_file`（verb `write`）的名字由决策者给定，
  而 `tool-rename-map.json` 的 37 词闭集里没有这两个动词；注册器按 GDR-16 L2 **拒绝注册**（第一次绿的构建里两个工具
  根本不在表里，`has_tool=false`，doctest 全红）。
* **选项**：(A) 改 map 扩闭集 —— **否决**：map 是唯一事实源且其 sha 进契约，改它等于偷偷改移植契约；
  (B) 不管动词 —— **否决**：等于让「闭集」变成口号，下一个新增可以随便发明动词；
  (C) **选中**：37 词列表**逐字不动**，新增动词只能经显式记录进入，且该记录同时出现在三处——
  `tool_registry.cpp` 的 `MCP_ADDED_TOOL_VERBS`、生成器的 `ADDED_VERB_EXTENSIONS`（陈旧记录即致命失败）、
  `docs/tool-groups-added.json` 的 `verb_extensions`（`--added` 要求每条都被组用到）。
* **影响 / 回滚**：新增动词有唯一入口且可 grep；回滚 = 删掉两处记录 + 两个工具改名（但那会违背决策者给定的名字）。

### 7.2 任务书要 `-32001`（已存在），GDR-14 把 `-32001` 读作「东西不在」——按任务书实现并报冲突

* **触发**：任务书 §1.2 ③ 明确要求「`overwrite:false` 且文件已存在 → `-32001` + 建议传 `overwrite:true`」，
  而 GDR-14 的定义是 `-32001` = 「找的具体东西不在」、`-32000` = 「状态挡住调用」——「目标已存在」属后者。
  另：`MCPToolError::not_found()` 会给 message 追加 `" not found"`，用它会产生
  `… already exists and 'overwrite' is false not found` 这种自相矛盾的句子。
* **选择**：**逐字执行任务书**（`-32001`），但**不用** `not_found()` 工厂，而是手工组装错误（code + 可读 message +
  `data.suggestion`，`tools/project_text_write.cpp` 的 `_already_exists`），并把语义冲突**留在报告里**请决策者裁定。
* **回滚点**：一行（换成 `MCPToolError::tool_state(...)`）；但改动会影响证据与验收判据，故不自行改。

### 7.3 `timeout_ms` 与框架上限：让工具**自己**回答 `timed_out:true`

* **触发**：契约允许 `timeout_ms` 到 600000，但传输层对 deferred 请求有全局上限
  `mcp_server/pending_timeout_ms`（默认 30000），而 `_effective_timeout()` **只会缩短** task 自己的期限
  （`mcp_jsonrpc.cpp:245-253`），且框架的到期判定发生在 `tick()` **之前**（`mcp_deferred.cpp:126-137`）。
  若什么都不做，调用者会收到框架的通用 `-32000 timeout`，而不是「你的构建被杀掉了」。
* **选择**：工具在**创建任务时**就取用同一套规则（`MCPServer::get_pending_timeout_ms()` + `MCPPendingTimeout::effective_ms`，
  为此外加了一个只读访问器），把 `effective = min(requested, ceiling)` 算出来，在 `effective − 400 ms` 自查到期并
  **真的 `OS::kill`**，回答 `timed_out:true`；响应同时给出 `timeout_ms` 与 `effective_timeout_ms`，让调用者看得见这次 clamp。
  400 ms 的余量来自「框架先查到期、再 tick」这一事实（doctest 与直播证据都实测到 1600/2000 这个数）。
* **未覆盖**：若某个工程的 `pending_timeout_ms` 被配成 < 1000（schema 允许的最小 `timeout_ms` 之下），工具会在
  更早的时刻超时——这是**诚实**的行为（服务器确实不可能等更久），但当前没有证据脚本覆盖该配置。

### 7.4 新增 schema 用 C++ Dictionary 构造（不用 JSON 文本）

见 §2.3：门① 抓到的真实缺陷。**回滚点**：若将来统一修 `JSON::parse`/`schema_with_integer_defaults` 的数值类型问题，
这里可以换回 JSON 字面量，届时门① 仍是守门人。

### 7.5 杀进程的边界（诚实声明）

`OS::kill()` 终止的是**本工具启动的那个子进程**（Windows 上 `TerminateProcess(dotnet.exe)`），
**不**保证终止 MSBuild 再派生的孙进程（引擎的 `OS` API 没有可移植的进程树终止）。证据给出的是
「直系子进程确实死了」（c11 的 pid 集合 + doctest ⑧ 的 `is_process_running`）。用 MSBuild target 里
`ping` 构造慢构建时，`ping` 本身可能活满自己的时长——这是**已知且已声明**的边界，不是「假装杀干净」。

### 7.6 其它小决策

* **stdout/stderr 的上限**：每流每工程 64 KiB，截断**标明**（`stdout_truncated`/`stderr_truncated`）；理由：一次构建
  的日志可能很长，响应不能无界增长。
* **非 UTF-8 字节**：替换成 `?` 并计数（`non_utf8_bytes`），因为 `String::utf8()` 遇到第一个坏字节就丢掉后面全部内容。
* **跨工程顺序**：多个 `.csproj` 按**排序后**顺序逐个构建，`exit_code` 为「全 0 则 0，否则第一个非零」，`commands`/`exit_codes`
  分别给出；证据里只有 1 个工程，多工程路径**未直播覆盖**（doctest 覆盖了多参数命令行与逐工程拼接的规则）。
* **`command` 的路径分隔符**：实测 `C:\Program Files\dotnet\/dotnet.exe`（`path_join` 用 `/` 拼在含 `\` 的 PATH 目录后）。
  这是**真实命令行**（子进程就是这样被启动的且构建成功），属显示层的观感问题，未改。
* **证据脚本的读者选择**：`project_search_file_contents` 的文本扩展白名单
  （`project_read_template.cpp:332-334`）**不含** `csproj`/`config`，所以 c13 的见证文件是 `.cfg`——这不是迁就测试，
  而是记录该读者的真实边界。

---

## 8. 交给决策者的待确认项（规范缺口 / 冲突）

1. **闭集动词**（§7.1）：GDR-28 第 4 条要不要明确写「新增动词必须显式登记，不得改 map 的 37 词闭集」？
2. **`-32001` 的语义**（§7.2）：任务书 §1.2 ③ 与 GDR-14 冲突，本批按任务书实现。请裁定是「保持」还是「改成 `-32000`」。
3. **`timeout_ms` 与 `mcp_server/pending_timeout_ms`**（§7.3）：是否要把这条 clamp 规则写进 GDR-20 的规范正文
   （现在只在实现与报告里）？
4. **`check_tool_groups.py --check-completeness` 的四种桶**是否需要写进 §26（现在规范只说 `171+N = 66+105+N`）？

## 9. 未构造 / 未覆盖项（显式声明，不是省略）

* **mono 的 doctest**：门③/④ 用的是 non-mono 二进制（`build_local.cmd` 的口径）。因此「无 C# 支持 → `-32000`」这条
  在 doctest 里被断言，而「有 C# 支持 → 真的构建成功」由**直播证据**（mono 引擎，§5.4）覆盖；mono 半边的回归由
  `mcp047_m3_mono_check.ps1` 单独覆盖（见 §6.2）。
* **多 `.csproj` 的直播构建**：证据工程只有 1 个 `.csproj`；顺序与聚合规则由 doctest 与命令行规则固定。
* **`configuration:"Release"`** 的直播构建：证据用的是 `Debug`；`Release` 走同一命令行规则（`-c Release`），
  doctest 固定了枚举校验与命令行生成。
* **`rescan:false`** 的直播分支：证据里 `rescanned=True`（mono 编辑器）；`false` 分支在游戏端点（无编辑器）自然为 false。
* **框架上限 < `timeout_ms` 的 clamp 配置**：见 §7.3。
* **MSBuild 孙进程**：见 §7.5。

## 10. 交接

* 交付物：生成器 v1.14.0 + 173 条契约 + `docs/tool-groups-added.json` + `check_tool_groups.py --added/--check-completeness`
  + 两个工具源文件与注册 + 8 个 doctest（+2 组用例）+ 证据脚本 + 契约 diff 脚本 + 本报告。
* 提交：`c1f3385daf`（机制）→ `2b2cbdeec2`（工具）→ `f38d240abb`（doctest）；本报告与证据脚本作为第四条提交。
  两个二进制的 `--version` 都自报 `f38d240ab`，即**包含全部编译期改动**的那个提交；第四条提交只增加
  `scripts/mcp052_*.ps1|py` 与本报告（不参与编译）。
* 未 push（禁止 push）；9877 未动；hof-rs 只读。
