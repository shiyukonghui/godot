# ACCEPTANCE-005 — 独立验收报告：TASK-005（框架清理 + 组 `project_read_files`）

- **验收者**：独立验收子代理（无实现者上下文，未参与实现，只读；除本文件外未修改任何文件）
- **被验收对象**：`feature/mcp-server-module` @ `c6fe7d7f00`（工作树 = HEAD，`git status --short` 只有开工前既有未跟踪物）
- **验收结论**：**FAIL**（见 §9 defects）。原因：**不是代码缺陷**——13 条 AC 的实质内容全部独立验证为真（含我用真实「重构前」二进制重采的 AC-2）；FAIL 来自
  **REPORT-005 §4「重构等价性证据」的证据完整性**：其中 2 条 `tools/list` 用例是用有损 ASCII 管道采集的（每例含 409 个 `?`），报告却把它当作「逐字节相同」的证据，
  并据此写出了错误的 13 工具 `tools/list` 字节数（报告写 3411，真实 4229）。另有报告 §9 deviation 15 无法复现。
- **核心事实（先说结论）**：6 个新工具的行为与契约、只读性、不可写性、TDD、五道门、迁移源语义对照**全部成立**；重构零可观察行为变化**成立**（我独立重建了 `8386726429^` 并重采，6/6 逐字节相同）。
- **环境**：仓库根 `F:\RustProjects\godot-mcp-pro\code\godot`；二进制 `bin\godot.windows.editor.x86_64.console.exe`（2026/9/22 03:00:15，晚于全部 mcp_server 源文件，未重建即可对应 HEAD）。
- **端口纪律**：全程 **9877 的监听者始终是 PID 36392**（开工前 / 每次门 / 收尾共 10+ 次 `netstat` 核对）；我自己的引擎只用 9888 / 9890 / 9891（+ 门①/门⑤ 自带的 9888/9889），全部由我自己 kill；scratch 全在 `%TEMP%`。

---

## 0. 我实际跑过的命令（不依赖任何报告结论）

| # | 命令 | 结果 |
|---|---|---|
| 1 | `git rev-parse --abbrev-ref HEAD` / `git log` / `git status --short` | 分支/提交/工作树与报告一致 |
| 2 | `netstat -ano -p TCP`（开工前 + 收尾 + 每道门前） | `9877 LISTENING 36392` 恒定 |
| 3 | `git show --stat` × 4（4 个提交） | 改动面全部在 `modules/mcp_server/**` |
| 4 | `git diff --stat 8386726429^ HEAD -- docs/tools_list.renamed.json docs/tool-rename-map.json` | 空 → 契约/映射未动 |
| 5 | `git diff 8386726429^ HEAD` （members 文件的增删行） | 只有 include/注释/改名调用点 |
| 6 | 自写 python（`%TEMP%\mcp-t005-acc\verify_transform.py`） | 逐字节重构等价性静态证明（§3） |
| 7 | `Select-String` 助手唯一性正向/反向/残留调用 | 4 定义 / 4 声明 / 0 反例 / 0 残留（§2） |
| 8 | `bin\...console.exe --headless --test --test-case="[MCPServer]*"` | **73 / 726 / 0 failed / EXIT=0** |
| 9 | `bin\...console.exe --headless --test` | **1499 / 425007 / 0 failed / EXIT=0** |
| 10 | `scripts\check_contract_subset.ps1 -Group project_read_files` | **3/3 PASS / EXIT=0**，9888 与 9889 各 19 工具 |
| 11 | `python docs\scripts\check_tool_groups.py` | **TOOL-GROUPS CHECK PASS / EXIT=0** |
| 12 | `scripts\accept_m1.ps1` × 2 | **A_EXIT=0 / B_EXIT=0，22/22 PASS，PASS 清单差异 0 行** |
| 13 | 自建 scratch 工程 + 30 条 `curl.exe --data-binary @file` 打 9888 | 30 条真实请求/响应（§5） |
| 14 | 自建 scratch 工程 + 只读不变式（调用 6 工具前后 31 文件全量 sha256） | **不变**（§6 AC-10） |
| 15 | `git worktree add --detach F:\mcp-t005-before-wt 8386726429^` + 全量重建 + 9891 重采 | 6/6 与报告 before/after 逐字节相同（§4） |
| 16 | 8 次 `--import` 变体（缓存/无缓存/带 `-e`/并发/换 cwd） | 全部 `EXIT=0`（§9 defect-2） |

---

## 1. AC-1 — 4 个助手在 `tools/` 下各只有一处定义

命令（`rg.exe` 不在 PATH，按任务书允许改用 `Select-String`；实际命令原样如下）：

```powershell
Select-String -Path modules\mcp_server\tools\*.cpp,modules\mcp_server\tools\*.h `
  -Pattern '^\s*(String|Vector<String>|Variant|void)\s+(join_path|split_lines|serialize_variant|collect_files_by_extension)\s*\('
Select-String -Path modules\mcp_server\tools\*.cpp,modules\mcp_server\tools\*.h `
  -Pattern 'static\s+(String\s+_join_path|Vector<String>\s+_split_lines|Variant\s+_serialize_variant|void\s+_collect_files_by_extension)'
Select-String -Path modules\mcp_server\tools\*.cpp,modules\mcp_server\tools\*.h `
  -Pattern '\b_join_path\b|\b_split_lines\b|\b_serialize_variant\b|\b_collect_files_by_extension\b'
```

真实输出：

```
tool_helpers.cpp:40: String join_path(const String &p_dir, const String &p_entry) {
tool_helpers.cpp:47: Vector<String> split_lines(const String &p_text) {
tool_helpers.cpp:66: Variant serialize_variant(const Variant &p_value) {
tool_helpers.cpp:174: void collect_files_by_extension(const String &p_path, const Vector<String> &p_extensions, bool p_include_addons, Vector<String> &r_out) {
tool_helpers.h:61: String join_path(const String &p_dir, const String &p_entry);
tool_helpers.h:68: Vector<String> split_lines(const String &p_text);
tool_helpers.h:73: Variant serialize_variant(const Variant &p_value);
tool_helpers.h:79: void collect_files_by_extension(const String &p_path, const Vector<String> &p_extensions,
=== NEGATIVE: old private helper defs (expect none) ===
=== any residual _join_path/_split_lines/_serialize_variant/_collect_files_by_extension callers (expect none) ===
```

**结论：AC-1 成立。** 4 个定义各 1 处（`tool_helpers.cpp`）+ 1 处声明（`tool_helpers.h`），无 `static _*` 反例，无残留旧调用点。

额外我做了**逐字节函数体等价性**（自写 python 花括号配对抽取函数体、去注释、空白归一、旧名去 `_` 后比较）：

```
=== A) old analysis helper bodies vs new tool_helpers bodies (normalised, rename applied) ===
_join_path                     identical=True  old_sha=2abca1e1ff532e89 new_sha=2abca1e1ff532e89
_split_lines                   identical=True  old_sha=5779720fbfb55665 new_sha=5779720fbfb55665
_serialize_variant             identical=True  old_sha=7897d44047b1db46 new_sha=7897d44047b1db46
_collect_files_by_extension    identical=True  old_sha=1f5defee958b708b new_sha=1f5defee958b708b
=== B) old template helper bodies vs new tool_helpers bodies ===
_join_path                     identical=True
_split_lines                   identical=True
_serialize_variant             identical=True
_collect_files_by_extension    ABSENT in old template
```

即：报告 §3 的「三份重复定义逐字节相同、template 无第四份」独立复核为真；`template` 的 `_trim_stars`/`_get_project_string`/`_get_screen_size`/`_has_reference_extension`
在 HEAD 与 `8386726429^` 均为**各 1 处定义**（实测 old/new defs 都是 1），未被顺手改动。

---

## 2. AC-2 — 重构前后逐字节等价（**我独立重建了重构前二进制**）

报告 §4 的证据目录 `%TEMP%\mcp-t005-equiv\` 仍在，我做了三件独立的事：

### 2.1 静态证明（最强的一层）

我用 git 抽出 `8386726429^` 与 HEAD 的两份成员文件，对**旧文件删除 4 个助手定义 + 把 4 个标识符改名**后，与 HEAD 文件做「去注释、去空行、去 `#include`、空白归一」的代码行序列比较：

```
=== project_read_analysis.cpp ===
  old-after-transform code lines = 746 ; new code lines = 746 ; EQUAL = True
=== project_read_template.cpp ===
  old-after-transform code lines = 468 ; new code lines = 468 ; EQUAL = True
```

另列出「helper 定义范围之外被删除的非注释行」，结论是**只有 9~10 行改名后的调用点**（`_join_path`→`join_path` 等），没有语义改动；
新增行只有 `#include "tool_helpers.h"` + 两段注释 + 同名改名调用点。`8386726429` 的 `--stat` 只含 4 个文件（两个成员文件 + `tool_helpers.{h,cpp}`），**`registration.cpp` 未被该提交触碰**，故 `tools/list` 的 name/description/inputSchema 不可能因重构改变。

### 2.2 真机重采「重构前」（本验收的主要额外工作量）

```powershell
git worktree add --detach F:\mcp-t005-before-wt 8386726429^     # = 59f6681316
Set-Location F:\mcp-t005-before-wt
D:\Anaconda\Scripts\scons.exe platform=windows target=editor tests=yes module_mono_enabled=no -j8
# SCONS_EXIT=0 ; INFO: Time elapsed: 00:14:08.16
# 起引擎（重构前二进制，端口 9891，同一个 equiv scratch 工程 / 同一批 .req 文件）
curl.exe -s -X POST -H "Content-Type: application/json" --data-binary "@...\before\<case>.req" --output <case>.resp http://127.0.0.1:9891/mcp
```

真实结果（`mybefore` = 我的重构前采集，`stored_before` = 报告 §4 的 before，`stored_after` = 报告 §4 的 after）：

```
=== MY independent BEFORE capture (pre-refactor build of 8386726429^, port 9891) ===
01_tools_list                                  mine= 4229 stored_before= 3411 ==False  stored_after==False  sha=d94a75f3565a6f08
02_project_get_info                            mine=  187 stored_before=  187 ==True  stored_after==True  sha=dfd2db52b7717f4f
03_project_get_settings                        mine= 1867 stored_before= 1867 ==True  stored_after==True  sha=595cdca41005cb39
04_project_search_file_contents                mine=  304 stored_before=  304 ==True  stored_after==True  sha=9eca624fea9851fe
05_project_get_statistics                      mine=  310 stored_before=  310 ==True  stored_after==True  sha=03858601f26b590e
06_project_detect_circular_dependencies        mine=  415 stored_before=  415 ==True  stored_after==True  sha=3dcf902b842d28dc
07_project_find_script_references              mine=  344 stored_before=  344 ==True  stored_after==True  sha=3f67207a1f133b00
MISMATCHES=1
```

再加我在 **HEAD 二进制**上重采 after（端口 9890，同一工程同一 `.req`）：

```
02_project_get_info                          recap=  187 stored=  187 shaEq=True
03_project_get_settings                      recap= 1867 stored= 1867 shaEq=True
04_project_search_file_contents              recap=  304 stored=  304 shaEq=True
05_project_get_statistics                    recap=  310 stored=  310 shaEq=True
06_project_detect_circular_dependencies      recap=  415 stored=  415 shaEq=True
07_project_find_script_references            recap=  344 stored=  344 shaEq=True
```

**所以 AC-2 的本体（「已实现两组各 3 个工具」共 6 条）我现在是**完全独立复现**的：
`重构前二进制(我) == 报告 before == 报告 after == HEAD 二进制(我)`，长度 + 逐字节 + sha256 全等。重构零可观察行为变化**成立**。

### 2.3 但报告 §4 的两条 `tools/list` 行是**有损采集**（→ defect-1）

`01 tools/list` 的差异不是行为差异，而是**采集管道损坏**，证据链如下。

报告自己的采集脚本 `%TEMP%\mcp-t005-equiv\capture.ps1` 里写着：

```powershell
& curl.exe -s -X POST -H "Content-Type: application/json" --data-binary "@$bodyFile" "$url" `
   | Out-File -FilePath $respFile -Encoding ascii -NoNewline
```

即**正是报告 §5.4 自称发现并已修复的那个有损管道**（`Out-File -Encoding ascii` 把非 ASCII 变成 `?`），而它被用于 §4 的 **before 与 after 两条腿的全部用例**。

原始字节（我自己数的）：

```
stored before : len=3411 0x3F=409 nonzero-high=0
my before     : len=4229 0x3F=0    nonzero-high=1227
=== arithmetic: len diff / 2 ===
409
```

- `stored before\01_tools_list.resp` 前 60 字节：`... 22 64 65 73 63 72 69 70 74 69 6f 6e 22 3a 22 3f` → 描述字段里就是字面 `?`（0x3F），且**全文件 0 个 >127 的字节**。
- 我的重构前采集：`4229` 字节、`0` 个 `?`、`1227` 个 >127 字节（`1227 / 3 = 409`，即 409 个非 ASCII 字符）。
- 算术恒等：`4229 − 3411 = 818 = 2 × 409` —— 每个字符从 3 字节 UTF-8 塌成 1 字节 `?`。**这是确定性证明，不是推断。**
- 由于 C++ 源码与契约里的 description 都是中文（门① 逐字 True 证明活体 description 与中文契约一致），任何由该源码构建的二进制都不可能输出 `?`。故 3411 只可能是采集损坏。

后果：
1. 报告 §4 表的 `01 tools/list`（3411/3411）与 `game 9889 tools/list`（3411/3411）两行，比较的是**两份被同样损坏的文件**；被 `?` 抹掉以后，不同的中文串会塌成同一串 `????`，因此这两行**不构成 `tools/list` 未被改变的证明**（真正的保证来自 §2.1 的静态等价性：重构提交根本没碰注册与描述）。
2. 报告 §4 末句「`tools/list` 的 3411 字节 / 13 条」是**事实错误**：真实值为 **4229 字节 / 13 条**（我用重构前二进制实测）。
3. 报告 §4 结论句「8/8 用例长度相等、逐字节相等、sha256 相等」中，有 2 例的字节不是真实响应字节。
4. 其余 6 例内容全为 ASCII，`-Encoding ascii` 对其无损，因此这 6 例有效 —— 与我的独立重采一致。

> 附带确认：门⑤ `case20` 的 `bytes=5393/5393` 是**干净**的（`accept_m1.ps1` 走 `Invoke-Mcp` 返回 .NET 字符串再 `UTF8.GetBytes`，不经 `Out-File`），与我从 HEAD 采到的 5392 字节（我的请求 `id` 只有 1 位）在同一量级，可信。

---

## 3. AC-3 — 6 个工具在 9888 与 9889 上 name/description/inputSchema 与契约逐字 True

我独立重跑门①（脚本未改，`git diff` 为空；采用并集语义）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\check_contract_subset.ps1 -Group project_read_files
```

```
group       : project_read_files
tools       : project_list_scripts, project_read_script, project_validate_script, project_read_resource, project_get_resource_preview, project_read_scene_file_content
implemented : 19 tool(s) across the groups marked implemented: ... project_read_scene_file_content
contract    : 171 entries
user editor on 9877 before run: pid=36392
[PASS] editor_9888_contract_subset  ... tools=19 ... project_list_scripts: name=True description=True inputSchema=True | ... | project_read_scene_file_content: name=True description=True inputSchema=True
[PASS] game_9889_contract_subset    ... tools=19 ... （6 条同样 name=True description=True inputSchema=True）
[PASS] guard_user_port_9877        pid_before=36392 pid_after=36392
group=project_read_files tools=6 contract=171
implemented_union=19 tools
3/3 checks passed
EXIT=0
```

我还亲自抽检了 curl 活体响应（§5 有全文）。用 python 把我的 `tools/list` 原始响应与契约逐条比较（不是比解析后的长度，而是比 UTF-8 字符串与排序后的 schema JSON）：

```
implemented union size = 19
tools/list raw bytes = 5392
live tools/list size   = 19
set equality (no extras, none missing) = True
live order == union order              = True
--- per-tool verbatim comparison (live vs contract) ---
project_list_scripts               name=True  desc=True  schema=True
project_read_script                name=True  desc=True  schema=True
project_validate_script            name=True  desc=True  schema=True
project_read_resource              name=True  desc=True  schema=True
project_get_resource_preview       name=True  desc=True  schema=True
project_read_scene_file_content    name=True  desc=True  schema=True
（其余 13 个已实现工具同样 name/desc/schema 全 True）
```

**结论：AC-3 成立**（两个端口、逐字、活体）。

---

## 4. AC-4 — live `tools/list` 恰等于 `implemented=true` 组的并集（19）

见上：`set equality = True`、`live order == union order = True`、`live size = 19`，并集来自 `docs/tool-groups.json`
（6 + 7 + 6 = 19：`project_read_template` 6、`project_read_analysis` 7、`project_read_files` 6）。**无多余、无缺失。**

---

## 5. AC-5 — 每个新工具的 doctest 覆盖（成功 / 缺参 -32602 / 底层失败 -32001+suggestion / 特有边界）

我逐行读了 `tests/test_mcp_server.h` 第 2343–2740 行（新增 8 个用例全部），并做了机械假通过扫描：

```powershell
Select-String -Path modules\mcp_server\tests\test_mcp_server.h `
  -Pattern 'skip|SKIP|TODO|FIXME|do not assert|not available' | Where-Object { $_.LineNumber -ge 2340 -and $_.LineNumber -le 2740 }
# (empty = none)
```

覆盖实况（我自己核对的断言，不是转述）：

| 工具 | 成功 | 缺参 | 底层失败 | 特有边界 |
|---|---|---|---|---|
| `project_list_scripts` | ✅ `count==scripts.size()`、fixture 子树**精确集合** | —（契约无必填参数，语义上不存在，报告 §7.4 已声明） | —（无错误路径） | ✅ `.hiddendir/` 与 `addons/plug/` 下钻、`upper.GD` 不被收（大小写敏感）、两次调用 canonical 相等 |
| `project_read_script` | ✅ `payload.size()==3`、`size==content.length()`、CRLF/中文保真、无 `lines` | ✅ `-32602` + message 逐字 | ✅ `-32001` + `data.suggestion` | ✅ `res://a/./b` 归一后回显 |
| `project_validate_script` | ✅ 平衡→`valid==true`、不平衡→`valid==false`+`error_text`（两种模式同答案） | ✅ `-32602` | ✅ `-32001` + `suggestion` | ✅ 真编译正负例另由门② 承载（编辑器/游戏各一例） |
| `project_read_resource` | ✅ `size()==3`、**无 `properties`** | ✅ `-32602` | ✅ `-32001` + `suggestion` | ✅ 窄语义钉死 |
| `project_get_resource_preview` | ✅ 64×32+`max_size=16`→16×8、默认 256 不缩放、真 base64 解码出 `89 50 4E 47` | ✅ `-32602` | ✅ `-32001` | ✅ `max_size=0`→`-32602`、类型错→`-32602`、非图片资源→`-32602` |
| `project_read_scene_file_content` | ✅ `size()==3`、首行 `[gd_scene`、含 `[node name="Main" type="Node2D"]` | ✅ `-32602` | ✅ `-32001`（message 含 `Scene file`）+ `suggestion` | ✅ 无 `lines` |

**假通过检查**：新增用例里没有「若 X 不可用则跳过断言」的写法；所有 `if (result.get_type() != Variant::DICTIONARY) { return; }`
都是常规类型守卫（后面紧跟的是断言，不是静默跳过）；`project_validate_script` 的用例在 doctest 的降级分支与编辑器真编译分支下**都**要求 `true`/`false`，且邻居断言 `payload["valid"].get_type()==BOOL`，不是硬编码恒真。

**一处覆盖强度提示（非缺陷，记入 risks）**：`project_get_resource_preview` 的 `-32001` 用例只断言 `code` 与 message，**没有再断言 `data.suggestion`**（其余 4 个适用工具都断言了）。
该字段由共享工厂 `MCPToolError::not_found` 产出，且被框架级 doctest 钉死（`test_mcp_server.h:1269-1272`）与线级逐字节用例钉死（`:1296-1297`），我另用真机 curl（§5 用例 28）确认 preview 的响应**确实带** `data.suggestion`。

**结论：AC-5 成立。**

---

## 6. AC-6 — TDD 红阶段真实性与 AC-7/AC-8 基线

**红阶段**（我核对的是 git 树与行号，不是报告的形容词）：

```powershell
git show --stat --oneline 4b144e6c1d        # -> 只改 tests/test_mcp_server.h（606+/8-）
git ls-tree -r --name-only 4b144e6c1d -- modules/mcp_server/tools | Select-String project_read_files
                                            # -> 空：红树里确实没有实现文件
git show 4b144e6c1d:modules/mcp_server/tools/registration.cpp | Select-String project_read
                                            # -> 只有 template / analysis 两行，没有 read_files
(git show 4b144e6c1d:modules/mcp_server/tests/test_mcp_server.h | Select-String 'TEST_CASE\(').Count
                                            # -> 75（含 2 个临时 SPIKE 探针）
git show 4b144e6c1d:modules/mcp_server/tests/test_mcp_server.h | Select-String SPIKE | Measure-Object
                                            # -> 27 处命中（探针确实在红树里）
```

失败原因核对（报告引用的三行，我在红树里逐行对齐）：

```
2346:
2347: TEST_CASE("[MCPServer] the project_read_files group is registered for both processes") {
...
2352: 	CHECK(registry.get_tool_count() == 19);          <- 报告引用 test_mcp_server.h(2352) 完全一致
...
2365: 	CHECK(registry.has_tool(names[i]));              <- 报告引用 test_mcp_server.h(2365) 完全一致
...
2380: 	CHECK_FALSE(tool_error.is_error());              <- 报告引用 test_mcp_server.h(2380) 完全一致
```

红树的注册表里没有新工具、新工具文件不存在、`tool-groups.json` 里 `project_read_files.implemented` 仍为 `false`
⇒ 失败原因只能是「功能不存在」，**不可能是编译错**（测试只用字符串工具名，不引用新头文件）。绿的 `69ccfef13e` 只删掉 87 行 = 2 个 SPIKE 用例及其专属 include
（`Select-String '^-' | Where-Object { $_ -match 'TEST_CASE' }` 命中 2，且当前树 `SPIKE|print_line` 命中 **0**），**没有删掉任何一个生产用例**。

**AC-7 / AC-8 基线**：我在 `REPORT-004` 里核到基线原文（65 例 / 607 断言；1491 例 / 424888 断言），当前实测：

```
[doctest] test cases:  73 |  73 passed | 0 failed | 1429 skipped      （65 → 73，只增）
[doctest] assertions: 726 | 726 passed | 0 failed |                  （607 → 726，只增）
[doctest] Status: SUCCESS!   EXIT=0
[doctest] test cases:   1499 |   1499 passed | 0 failed | 3 skipped   （基线 1491，只增）
[doctest] assertions: 425007 | 425007 passed | 0 failed |             （基线 424888，只增）
[doctest] Status: SUCCESS!   EXIT=0
```

**结论：AC-6 / AC-7 / AC-8 成立**（AC-6 的断言计数 676 需在红树构建才能复现，我只复核了用例数 75 与失败行号——见 risks）。

---

## 7. AC-10 — 只读不变式

**测试侧**（我读了 `the file readers never write to the project`，第 2706–2739 行）：`before.size()==11` 是**硬断言**，
调用 6 个工具后 `after.size()==before.size()` 且 `canonical(after)==canonical(before)`。不是「只在有条件时断言」。

**我自己的真机侧**（比 doctest 更强：真实编辑器进程、包含 `.godot/` 缓存、含 sha256 全量比对）：

```powershell
# 起 bin\...console.exe --headless -e --path %TEMP%\mcp-t005-acc\proj --mcp-port=9888
# warm-up 后快照，跑 30 条请求（含 6 个工具的成功/缺参/底层失败/边界），再快照
SNAPSHOT_BEFORE_FILES=31
...
（30 条请求，含对 .gd 调用 ResourceLoader 的用例 21）
SNAPSHOT_AFTER_FILES=31
READONLY_INVARIANT_9888=True (project file list + hashes unchanged)
```

即：**31 个文件（含 `.godot/**`）的路径 + 长度 + sha256 在调用前后完全不变**，包括被 `ResourceLoader::load` 加载 `.gd` 之后（没有生成 `.uid`，也没有写 `.import`）。
**结论：AC-10 成立。**

---

## 8. AC-9 / AC-11 / AC-12 / AC-13

### AC-9 收口门 ×2（**独立重跑**，未用报告输出）

```
RUN A EXIT=0
RUN B EXIT=0
PASS_A=22 PASS_B=22
PASS_LISTS_IDENTICAL=True
implemented tools = 19; contract = 171; known_deviation = per-batch verbatim gate only
case20: pid_first=52988 pid_second=40856 tools=19 bytes=5393/5393 byte_identical=True
        sha256_first=768401f893bfa55a7d066cc71dc0edf39b96230138dad5deee1f11d3bffb07b9
        sha256_second=768401f893bfa55a7d066cc71dc0edf39b96230138dad5deee1f11d3bffb07b9
guard_user_port_9877: listening=True pid_before=36392 pid_after=36392   （A、B 两次相同）
```

22 条 PASS 清单（A/B 各一份，`Compare-Object` 差异 0 行）：
`case1..case11, case15..case20, case12, case13, case14, guard_user_port_9877, gate_scope_declared`。

硬编码工具数核对：

```powershell
Select-String -Path modules\mcp_server\scripts\accept_m1.ps1 -Pattern '\b(13|19)\b'
54: #      re-captured as clean UTF-8 (GDR-13) ...
156: # that emits mojibake (GDR-13) ...
275: if ($Bytes[$i] -eq 13 -and ...)     # CR 字节值
925: # --- case 19 (GDR-12.4) ...
1046: # --- case 13: game process without --mcp-port must not listen ...
git diff 4b144e6c1d 69ccfef13e -- modules/mcp_server/scripts/accept_m1.ps1   # 只有 $ToolNames 追加 6 个名字（+7/-1）
```

`$ToolNames` 现为 19 个（第 76–94 行），工具数一律走 `$ToolNames.Count`（第 166/606/1005/1110 行），**没有任何字面量 13 是工具数，也没有任何断言被放松**。
**AC-9 成立。**

### AC-11

```
GROUP   project_read_files           channel=project      mutating=False implemented=True  tools=6
ASSERT  every B1 tool appears exactly once: PASS (duplicates=0, missing=0, foreign=0)
ASSERT  every name exists in the 171 entry contract: PASS
ASSERT  every group is one channel + one mutating value: PASS
ASSERT  41 == 42 - 1: PASS
BYTES 5441
SHA256 5445d39a117626f8ad001dd588b91c1e15784d53bce4d1ef8595dd72d00e1da9
TOOL-GROUPS CHECK PASS   EXIT=0
```

`git diff 8386726429^ HEAD -- docs/tool-groups.json` = **只有 `implemented: false → true` 一行**（5442 → 5441 字节）。
**AC-11 成立。**

### AC-12 — 报告格式与「重构等价性证据」节

- PLAYBOOK §4 要求：`status` / `commits` / 逐工具表 / 红绿证据 / 五道门真实输出 / 三类证据 / sha256 / `deviations` / `blockers` / `next_step_recommendation` —— **全部存在**（我 grep 了 1–12 的标题）。
- 「重构等价性证据」节（报告 §4）**存在**，且确实是同 scratch 工程、同端口、同请求体（我逐一 hash 了 `before/*.req` 与 `after/*.req`：两轮字节相同；工程是同一个 `%TEMP%\mcp-t005-equiv\proj`）。
- **但该节含 2 条有损采集行并给出错误字节数**（§2.3）。因此「该节作为可核对证据」这一目的**未达成** ⇒ 本 AC 判 **false**（详见 §9 defect-1；修正后即可翻为 true）。
- 报告 §8 的文件指纹表我全量重算，**10/10 与报告完全一致**：

```
    4869  9c01df9112689b102c14d7d36e517a06fa9c9cbe2f3848eada1c5556a6685d3c  tool_helpers.h
    6805  b38369b0256576755445f5fe6e3a6a0ee7c8f8a17689160d767d1ce2e36d923c  tool_helpers.cpp
    3403  1f83cfa7f898c2cd4dd3bd6fcabaccef44c3f6888f1ae25affb542de80f14db4  project_read_files.h
   23354  250f24b3848b5a7eef04331d7ea7ca264aa80ce1e1519458c6472a43bcb3e868  project_read_files.cpp
   38575  7302b78e68476fb4fc71d403db0f27da9ed5b43a19a851fe3ed54641ede10cb4  project_read_analysis.cpp
   22401  048184815b6159e8196bf659008698e7a05d56e74e6f862f8a046281615e95e6  project_read_template.cpp
    2746  a0064e8b2556f99452b8caae747fa131e76dfaca4e6469391d4cbcc31c343df5  registration.cpp
  123154  8ac05dcfc40b460142ffb062ff2e052d9412d5ecb697c203aabef7c7125cb681  test_mcp_server.h
    5441  5445d39a117626f8ad001dd588b91c1e15784d53bce4d1ef8595dd72d00e1da9  tool-groups.json
   56134  618996187628029cf493c9fc907697f278279b700557ebfe3db2f931f2913abf  accept_m1.ps1
```

### AC-13 — 端口纪律 9877 = PID 36392

我自己的门① 输出 `user editor on 9877 before run: pid=36392` 与 `pid_before=36392 pid_after=36392`；
我自己的门⑤ 两次都是 `listening=True pid_before=36392 pid_after=36392`；我全程 10+ 次 `netstat` 抽查均为 `127.0.0.1:9877 LISTENING 36392`，收尾亦然（用户进程 `Godot_v4.7.1-stable_mono_win64` PID 36392 一直健在）。
**AC-13 成立。**

---

## 9. defects（现象 + 复现命令 + 真实输出 + 严重度）

### DEFECT-1（严重度：中）REPORT-005 §4「重构等价性证据」中 2 条 `tools/list` 用例系有损采集，且报告给出错误的工具数/字节数

- **现象**：报告 §4 把 `01 tools/list`（before=3411 / after=3411 / sha `cf74a90b…`）与 `game 9889 tools/list`（3411/3411）列为「逐字节相同」的等价性证据；
  但这两份文件是用 `Out-File -Encoding ascii` 采集的，每个中文占 1 字节 `?`（共 409 个），并且报告据此刻画「`tools/list` 的 3411 字节 / 13 条」。
  13 工具 `tools/list` 的真实字节数是 **4229**（我用从 `8386726429^` 新构建的二进制实测）。
- **复现命令与真实输出**：

```powershell
Get-Content "$env:TEMP\mcp-t005-equiv\capture.ps1"    # 采集用的是：
#   & curl.exe -s ... --data-binary "@$bodyFile" "$url" | Out-File -FilePath $respFile -Encoding ascii -NoNewline

$b=[IO.File]::ReadAllBytes("$env:TEMP\mcp-t005-equiv\before\01_tools_list.resp")
"stored before : len=$($b.Length) 0x3F=$((($b|?{$_ -eq 63}).Count)) nonzero-high=$((($b|?{$_ -gt 127}).Count))"
# -> stored before : len=3411 0x3F=409 nonzero-high=0

$m=[IO.File]::ReadAllBytes("$env:TEMP\mcp-t005-acc\mybefore\01_tools_list.resp")   # 我用 8386726429^ 的新构建采的
# -> my before     : len=4229 0x3F=0 nonzero-high=1227
# (4229-3411)/2 = 409   ==  1227/3 = 409      # 每个非 ASCII 字符塌成 1 个 '?'
```

  前 60 字节原始 dump 亦可直接看到 `... 64 65 73 63 72 69 70 74 69 6f 6e 22 3a 22 3f`（`"description":"?`）。
- **影响**：
  1. 该 2 行的「before == after」比较的是两份同样被损坏的文件，不同中文串会塌成同一个 `?` 串，**不构成 `tools/list` 未变的证据**（真正的保证来自：重构提交 `8386726429` 的 `--stat` 只含 4 个文件，未触碰注册与描述，且我对两个成员文件做了代码级等价性证明）；
  2. 报告 §4 的 3411 字节 **与事实不符**（真实 4229）；
  3. 报告 §4 结论句「8/8 用例长度相等、逐字节相等、sha256 相等」中有 2 例的字节不是真实响应字节。
- **注**：**AC-2 的本体（6 个工具调用）不受此缺陷影响**——那 6 例全为 ASCII、有损管道对其无损，且我已用真实重构前二进制 6/6 复现。
- **修复建议（成本很低，不需要改代码）**：用 `curl.exe --output`（二进制安全）重采 `%TEMP%\mcp-t005-equiv\before|after|after_game`，或直接采用本报告 §2.2 的我方重采结果，
  把报告 §4 的 2 行更正为 13 工具 `tools/list` = **4229 字节**、并说明「重构前/后 `tools/list` 未变」的依据是静态等价性 + 6 个 ASCII 用例的真机逐字节复现。

### DEFECT-2（严重度：低）报告 §9 deviation 15 的 `--import` 崩溃无法复现

- **现象**：报告称 `bin\...console.exe --headless --path <evidence proj> --import` 以 `EXIT=-1073741819`（0xC0000005）结束。我在 8 种变体下均得到 `EXIT=0`。
- **复现命令与真实输出**（真实工程用报告自己的证据工程副本，含/不含 `.godot`、含/不含 `-e`、换 cwd、并发开着一个编辑器进程）：

```
(a) fresh (no .godot), --headless --path X --import        -> A_EXIT=0
(b) fresh (no .godot), --headless -e --path X --import     -> B_EXIT=0
(c) cached sidecars kept, no .godot, from repo root        -> C_EXIT=0
(d) same project, cwd=%TEMP%                               -> D_EXIT=0
(并发：9888 上已有编辑器时再跑 --import)                    -> IMPORT_CONCURRENT_EXIT=0
(我自己的 scratch 工程，有 .godot 缓存)                     -> IMPORT_EXIT=0
```

  日志尾部是正常的 `[ DONE ] loading_editor_layout`，无 access violation、无 `is_cmdline_mode` 报错；
  `%TEMP%\mcp-t005-evidence` 与 `%TEMP%\mcp-t005-equiv` 下也**没有留下任何崩溃日志**（`Select-String 'C0000005|access violation|is_cmdline_mode'` 命中 0）。
  另注：`editor_node.cpp:6731` 的 `is_cmdline_mode()` 实现是 `ERR_FAIL_NULL_V(singleton, false);` —— 它打印告警而**不会**崩溃，报告把它描述为「栈顶」在语义上也对不上。
- **影响**：该条是报告自称的「环境观察」，**不影响任何 AC**，且报告由它得出的操作结论（门② 不依赖 import 缓存）被我的成功 `--import` 与全部工具调用反过来支持。但它是报告里一条**与我的观测不符的事实陈述**。

### DEFECT-3（严重度：信息）`--import` 默认会尝试绑定用户的 9877

- 我跑 `--import` 不带 `--mcp-port` 时，stderr 出现：
  `WARNING: [MCP] bind failed on 127.0.0.1:9877; MCP server disabled`（`mcp_server.cpp:391`）。
  行为是**优雅失败**（没有干扰 PID 36392，事后核对 9877 监听者仍是 36392），但任何 `--headless -e` 忘记带 `--mcp-port` 的调用都会去碰用户端口。
  报告 §7.1 的证据流程都带了 `--mcp-port`，因此未违规；此处仅作为后续流程的提醒，不计入报告缺陷。

---

## 10. risks

1. **AC-6 的断言计数（红阶段 676 断言）我未能独立复现**：复现它需要在红树 `4b144e6c1d` 上重新构建。我反证的是更硬的点——红树只改测试文件、无实现文件、无注册、组标记仍 `false`、且报告引用的 3 个失败断言行号（2352/2365/2380）与红树逐字对齐、红树含 75 用例（含 2 个 SPIKE 探针，HEAD 为 73、探针 0 处）。**推断**：676 这个数字本身未独立验证。
2. **`project_get_resource_preview` 的 doctest 未复断言 `data.suggestion`**（其余 4 个工具都断言了）。行为正确性由框架级 doctest + 门② 真机响应（我的 curl 用例 28 含 `data.suggestion`）覆盖，属覆盖强度差异而非行为缺陷。
3. **只读不变式的「真机」覆盖面**：AC-10 的机械钉死发生在 doctest 进程（设计如此）；我在真实编辑器进程上补做了 31 文件全量 sha256 不变验证（本次验收新增）。
   **未覆盖**：真实**游戏**进程（9889）上的文件列表不变式。报告 §7.3 已证明 21 例响应 editor==game 逐字节相同，故风险很低，但严格说该侧未钉。
4. **`project_validate_script` 的降级分支**在真实进程里从不触发（编辑器/游戏语言均已初始化），因此该分支只在 doctest 里被执行；其中 `error_text` 固定为 `"ERR_PARSE_ERROR"`、`message` 明说「未编译」，是**降级语义**而非迁移源语义。已在报告 §9 deviation 4/5/6 披露。
5. **`_error_identifier()` 是手写映射**（13 个 Error 值），未映射到的值回落为引擎散文描述；迁移源用的是 Rust `{:?}` 标识符。已在报告 §9 deviation 6 披露，属可接受偏差。
6. **`size` 语义**：`project_read_script` / `project_read_scene_file_content` 报**字符数**而非 UTF-8 字节数（我用报告证据工程里的 `cjk.gd` 复核：磁盘 63 字节、解码 55 字符、响应 `"size":55`；Rust 迁移源会报 63）。属 DESIGN §B.2 明定的偏差，已登记。
7. **跨进程确定性**只由门⑤ `case20`（同一构建、重启进程）覆盖；**跨构建**的 `tools/list` 字节稳定性不在本任务范围（`_meta.order_normative=false`）。

---

## 11. 我做的对抗性用例（报告里没有的）与真实响应片段

工程 `%TEMP%\mcp-t005-acc\proj`（自建；含 `.hidden/secret.gd`、`addons/plug/a.gd`、`scripts/upper.GD`、`shaders/effect.gdshader`、64×32 PNG、`icon.svg`、`plain.txt`、`simple.tres`、`main.tscn`）。采集一律 `curl.exe --data-binary @file`。

| 用例 | 真实响应（片段） | 判定 |
|---|---|---|
| `res://scripts/./valid.gd` | `{"path":"res://scripts/valid.gd",...,"size":67}` | 归一 ✅ |
| `res://scripts//valid.gd` | `{"path":"res://scripts/valid.gd",...}` | 归一 ✅ |
| `res://../secret.gd` | `{"error":{"code":-32602,"message":"Parameter 'path' must not walk upwards with '..', got 'res://../secret.gd'"}}` | 拒绝 ✅ |
| `C:/Windows/win.ini` | `-32602 "must address the project ('res://...')"` | 拒绝 ✅ |
| `path: 123`（数字） | `-32602 "Parameter 'path' must be a string, got float"` | ✅（`float` 字样是框架既有行为，见报告 §7/REPORT-004 同款） |
| `path` 指向目录 `res://scripts` | `-32001 "File 'res://scripts' not found"` + suggestion | ✅ 不崩、不写 |
| `max_size: -5` | `-32602 "must be a positive integer, got -5"` | ✅ |
| `max_size: 1.5` | `-32602 "must be an integer, got float"` | ✅ |
| `max_size: 0` | `-32602 "must be a positive integer, got 0"`（门② 证据 17 / 116 字节，我复核过原始字节） | ✅ |
| `.svg` 预览 `icon.svg` | `{"format":"png","height":32,"width":32,"image_base64":"iVBORw0KGgo…"}` | ✅ |
| 大写扩展名 `res://images/small.PNG` | 走图片分支，`width=64,height=32`，`path` 原样回显 | ✅ |
| 非图片资源 `simple.tres` | `-32602 "Resource type 'Resource' does not have an image preview"` | ✅ |
| `.gd` 当预览对象 `valid.gd` | `-32602 "Resource type 'GDScript' does not have an image preview"`（且未生成 `.uid`） | ✅ |
| `list_scripts` | `{"count":5,"scripts":["res://.hidden/secret.gd","res://addons/plug/a.gd","res://scripts/broken.gd","res://scripts/valid.gd","res://shaders/effect.gdshader"]}` | ✅ **仅跳过 `.`/`..`**，`.hidden` 与 `addons` 都下钻，`upper.GD` 不收，`.gdshader` 收 —— 与迁移源 `collect_gd_files`（`script.rs:54-66`，逐行读过）**逐条一致** |
| `read_scene_file_content` 指向 `.gd`（非 `.tscn`） | 返回全文 3 键 | ✅ 与迁移源一致（不校验扩展名） |
| `validate_script` 缺失文件 | `-32001 "Script 'res://scripts/nope.gd' not found"` + suggestion | ✅ |
| `read_resource` 缺失 / `plain.txt` | `-32001 "Resource '…' not found"` + suggestion | ✅（`plain.txt` 的措辞怪癖已由报告 §9 deviation 9 披露） |

迁移源逐条对照（我读了 Rust 源）：`script.rs:54-66/68/73/158`、`resource.rs:75-92/278-363`、`scene.rs:228-244` ——
参数名/必填性、返回键与形状（`list_scripts` 是**路径字符串数组**、`read_*`/`scene` 恰好 3 键且**无行号**、`read_resource` 恰好 3 键且**无 `properties`**、`preview` 恰好 5 键）、
扩展名集合与小写化、`min(max/w,max/h)` 缩放公式、`-32602`/`-32001`/`-32603` 的错误分类，**报告 §1 逐工具表的每一格我都与源码对上了**，未发现未声明的差异。

---

## 12. 工作树与改动面（收尾核对）

```powershell
git worktree list     -> F:/RustProjects/godot-mcp-pro/code/godot  c6fe7d7f00 [feature/mcp-server-module]   （只有主工作树）
Test-Path .git\worktrees -> False
git status --short
?? .graphifyignore
?? build-m0.cmd
?? graphify-out/
?? install-deps-m0.cmd
?? modules/mcp_server/docs/spec/
```

- 与开工前**逐行相同**：只多出本验收文件 `modules/mcp_server/docs/reports/ACCEPTANCE-005-project-read-files.md`（本阶段允许写的唯一文件）。
- 我用于复现 AC-2 的临时 worktree `F:\mcp-t005-before-wt`（含全量构建产物）与其中引擎进程**已删除 / 已 `git worktree prune`**，未在仓库留下任何改动或元数据。
- 我为验收创建的所有进程（9888→43228/50140、9890→41428/47376、9891→11908/53052、并发测试→39668）均已 kill；收尾 `netstat` 无 9888/9889/9890/9891 监听者，`9877` 仍是 `36392`。

---

## 13. 最终判定

| AC | 判定 | 一句话依据 |
|---|---|---|
| AC-1 | pass | 4 定义/4 声明/0 反例/0 残留，且函数体逐字节等价 |
| AC-2 | pass | **我重建了 `8386726429^` 并重采：6/6 与报告 before 与 after 以及 HEAD 重采逐字节相同**（但 §4 的 2 条 `tools/list` 行无效，见 DEFECT-1） |
| AC-3 | pass | 门① 独立重跑 3/3 PASS，9888/9889 各 19 工具、6 条 name/desc/schema 全 True + 我用 python 逐字复核活体响应 |
| AC-4 | pass | 活体 `tools/list` 与 `implemented=true` 并集集合相等、顺序相等、19 条 |
| AC-5 | pass | 逐用例核对 4 类覆盖；假通过扫描 0 命中 |
| AC-6 | pass | 红树只改测试、无实现、无注册、组标记 false；报告引用行号 2352/2365/2380 与红树逐字一致；红 75 例含 2 探针、HEAD 73 例 0 探针 |
| AC-7 | pass | 73 / 726 / 0 failed / EXIT=0（基线 65 / 607） |
| AC-8 | pass | 1499 / 425007 / 0 failed / EXIT=0（基线 1491 / 424888） |
| AC-9 | pass | 我自己连跑两次 A/B EXIT=0，22/22，PASS 清单差异 0 行；19 名单、无硬编码 13、断言未放松 |
| AC-10 | pass | doctest 11 文件硬断言 + 我补的真机编辑器进程 31 文件全量 sha256 不变 |
| AC-11 | pass | `implemented=true`；`check_tool_groups.py` PASS/EXIT=0；`tool-groups.json` 只差一个词 |
| AC-12 | **false** | 节存在、同工程同端口同请求体，但其中 2 条行是有损采集、且字节数与事实不符（DEFECT-1） |
| AC-13 | pass | 我的门①/门⑤ 均 `pid_before=36392 pid_after=36392`，全程 netstat 抽查一致 |

**verdict = fail**：不是因为交付代码有问题（代码、契约、只读性、TDD、五道门、迁移源语义对照全部成立，且 AC-2 的关键行为等价性由我用真实重构前二进制独立复现），
而是因为 **REPORT-005 §4 的证据表含 2 条被有损管道损坏的 `tools/list` 用例、并写出与事实不符的 13 工具字节数（3411 vs 4229）**，触发验收规则中「发现报告与事实不符即 fail」；
另有报告 §9 deviation 15 的 `--import` 崩溃陈述无法复现。修正缺陷只需重采证据并更正报告 §4（+ §9 deviation 15 措辞），**无需改动任何实现代码**。

---

## 第二轮独立复核（TASK-005 修复轮；**append-only**，未改动上文任何内容）

- **复核者**：独立验收子代理（第二轮，**全新上下文**，未参与实现、未受第一轮结论影响）
- **复核对象**：`feature/mcp-server-module` @ `c9800ade81`（含勘误提交 `3a3c823f26`）
- **纪律**：只读；除本节外**未修改/未提交任何文件**。端口：开工与收尾均为 `127.0.0.1:9877 LISTENING 36392`
  （`Godot_v4.7.1-stable_mono_win64`），全程**未连接、未 kill、未重启** 9877；自用端口 9888/9890/9891
  （＋门①/门⑤自带的 9888/9889），全部由我自己 kill；scratch 全在 `%TEMP%`。
- **总判定：`PASS`**（第一轮 DEFECT-1 已按字节保真重采并更正，DEFECT-2 撤回成立；13 条 AC 全部为真）

### R1. AC-12 的关键：用**自建 worktree**重建 P0/P1，独立复现重构等价性

第一轮已指出「HEAD 含 6 个新工具，13 条 before 与 19 条 HEAD 本就不应相等」，故对照点只能是
`8386726429`（重构提交本身）。我**没有**采信报告结论，而是自己重建两个点：

```powershell
git worktree add --detach F:\mcp-t005-acc2-p0 8386726429^   # HEAD is now at 59f6681316
git worktree add --detach F:\mcp-t005-acc2-p1 8386726429    # HEAD is now at 8386726429
# 两个 worktree 各自全量构建（并发，-j8；pwsh）
D:\Anaconda\Scripts\scons.exe platform=windows target=editor tests=yes module_mono_enabled=no -j8
# -> P0: scons: done building targets.  INFO: Time elapsed: 00:23:41.63  SCONS_P0_EXIT=0
# -> P1: scons: done building targets.  INFO: Time elapsed: 00:23:46.04  SCONS_P1_EXIT=0
# 自建 scratch 工程 + 请求体（同一份，两轮复用）；采集一律让 curl 直接写文件：
curl.exe -s -o <resp> -X POST -H "Content-Type: application/json" `
  --data-binary "@...\bodies\01_tools_list.json" http://127.0.0.1:<port>/mcp
```

真实采集（`mine` = 我的 50 字节 body；`report` = 报告 §4 那支 58 字节 body，
sha256 `17b0e4fe…`，我复核过其字节与报告 §4 表末一致）：

```
RESP HEAD_editor_9890_report len= 5392 tools= 19 0x3F=  0 high= 1413 sha=1a055b3214e45f32a357cd1fb55de173da2d493c0b687342a7916ca89111fc9f
RESP P0_editor_9890_mine     len= 4229 tools= 13 0x3F=  0 high= 1227 sha=d94a75f3565a6f08aa2614cfe4df928f013edffd674734089cee1a9a1d3baa80
RESP P0_editor_9890_report   len= 4229 tools= 13 0x3F=  0 high= 1227 sha=d94a75f3565a6f08aa2614cfe4df928f013edffd674734089cee1a9a1d3baa80
RESP P0_game_9891_mine       len= 4229 tools= 13 0x3F=  0 high= 1227 sha=d94a75f3565a6f08aa2614cfe4df928f013edffd674734089cee1a9a1d3baa80
RESP P0_game_9891_report     len= 4229 tools= 13 0x3F=  0 high= 1227 sha=d94a75f3565a6f08aa2614cfe4df928f013edffd674734089cee1a9a1d3baa80
RESP P1_editor_9890_mine     len= 4229 tools= 13 0x3F=  0 high= 1227 sha=d94a75f3565a6f08aa2614cfe4df928f013edffd674734089cee1a9a1d3baa80
RESP P1_editor_9890_report   len= 4229 tools= 13 0x3F=  0 high= 1227 sha=d94a75f3565a6f08aa2614cfe4df928f013edffd674734089cee1a9a1d3baa80
RESP P1_game_9891_mine       len= 4229 tools= 13 0x3F=  0 high= 1227 sha=d94a75f3565a6f08aa2614cfe4df928f013edffd674734089cee1a9a1d3baa80
RESP P1_game_9891_report     len= 4229 tools= 13 0x3F=  0 high= 1227 sha=d94a75f3565a6f08aa2614cfe4df928f013edffd674734089cee1a9a1d3baa80

--- 逐字节（对原始字节数组逐 index 比较）---
P0_editor vs P1_editor (report body) : EQUAL
P0_game   vs P1_game   (report body) : EQUAL
P0_editor vs P0_game   (report body) : EQUAL
P1_editor vs P1_game   (report body) : EQUAL
P0_editor vs HEAD_editor (report body): len NE (4229 vs 5392)      <- 13 条 vs 19 条，预期不等
```

**独立结论**：13 条 `tools/list` = **4229** 字节、0 个 `?`、1227 个 >127 字节、sha256
`d94a75f3565a6f08aa2614cfe4df928f013edffd674734089cee1a9a1d3baa80`；**P0 与 P1 在编辑器与游戏两个进程上
长度相等 + 逐字节相等 + sha256 相等**；HEAD 是 19 条 / **5392** 字节 / sha `1a055b32…`，**不与 P0 相等（预期，
不是缺陷）**。即报告 §4.1 的对照点判定（P1 = `8386726429`，不是 HEAD）**正确**，且其 P0/P1/P2 三组数字与我
自查的**报告 §4.1 captures、第一轮验收 `%TEMP%\mcp-t005-acc\mybefore`** 逐字节相同（三条互相独立的构建链互证）。
（我的构建产物自身 sha256 与报告 §4.1 的二进制 sha 不同——worktree 路径不同导致嵌入路径不同，构建非位可复现，
报告从未主张二进制可复现，**不构成缺陷**。）

### R2. §4 勘误的诚实性与残留检查（机械核对，非阅读报告措辞）

我直接对**磁盘上的原始字节**重算（python `%TEMP%\mcp-t005-acc2\check_artifacts.py`）：

```
== request body 01_tools_list.json ==   len=58 0x3F=0 high=0 sha=17b0e4fe8898d0f7b668dd1437d3078266e8d170bc490ebbb012e2bbbcd7b913
== stored (lossy) before/after/after_game ==   len=3411 0x3F=409 high=0  sha=cf74a90b9708093e99c9a622e761d56411a056dcf9e186c20b14587e9ed6df72
== errata captures ==
  before_editor_9890.resp     len=4229 0x3F=0 high=1227 sha=d94a75f3565a6f08aa2614cfe4df928f013edffd674734089cee1a9a1d3baa80
  before_game_9889.resp       len=4229 0x3F=0 high=1227 sha=d94a75f3565a6f08aa2614cfe4df928f013edffd674734089cee1a9a1d3baa80
  refactor_editor_9890.resp   len=4229 0x3F=0 high=1227 sha=d94a75f3565a6f08aa2614cfe4df928f013edffd674734089cee1a9a1d3baa80
  refactor_game_9889.resp     len=4229 0x3F=0 high=1227 sha=d94a75f3565a6f08aa2614cfe4df928f013edffd674734089cee1a9a1d3baa80
  after_editor_9890.resp      len=5392 0x3F=0 high=1413 sha=1a055b3214e45f32a357cd1fb55de173da2d493c0b687342a7916ca89111fc9f
  after_game_9889.resp        len=5392 0x3F=0 high=1413 sha=1a055b3214e45f32a357cd1fb55de173da2d493c0b687342a7916ca89111fc9f
== arithmetic ==  4229-3411 = 818 ; /2 = 409.0 ; 1227/3 = 409.0
```

- **污染根因诚实登记**：报告 §4.1(1) 给出的「每个非 ASCII 字符从 3 字节 UTF-8 塌成 1 个 `?`」由
  `0x3F 计数 = 409 = (4229−3411)/2 = 1227/3` 这一**恒等式**独立证实；原始采集脚本 `capture.ps1:47` 的
  `| Out-File -Encoding ascii -NoNewline` 我读过（`%TEMP%\mcp-t005-equiv\capture.ps1`）。
- **append-only**：`git diff --unified=0 c6fe7d7f00 HEAD -- REPORT-005…` 的删除行只有 7 行，且每一行的原文都
  以 **删除线 `~~…~~` + 「已作废」标注**保留在 §4，或被 §4.1 引用；**没有任何一条原始记录被抹掉**。
- **无残留旧值当作有效证据**：全 `docs/` 检索 `3411|cf74a90b|5393`，命中全部落在「已作废」行、§4.1 的
  污染分析与本验收文件里；`cf74a90b…` 只出现在 §4 的两行删除线内。§4 结论句已改为
  「6 个 ASCII 工具调用（02–07）+ 2 个重采的 `tools/list`」，并显式承认原句「8/8」中的 2 例无效。
- **`5393` 与 `5392` 的差异归因核对**：`accept_m1.ps1:973` 的 case20 body 是
  `{"jsonrpc":"2.0","id":77,"method":"tools/list","params":{}}`（`id` 两位），比 §4.1 的 `id=1` 恰多 1 字节，
  故 5393/`768401f8…` 与 5392/`1a055b32…` 都是各自请求的真实字节 —— 报告 §4.1(5) 的解释**与源码一致**。

### R3. DEFECT-2（`--import` 崩溃主张）撤回：我复跑 7 次，全部 EXIT=0

```powershell
# 工程为报告证据工程的副本；每条都显式带 --mcp-port=9890（绝不触碰 9877）
& $exe --headless [-e] --path <proj> --import --mcp-port=9890 ; $ec = $LASTEXITCODE
Select-String -Path <out>,<err> -Pattern 'C0000005|access violation|is_cmdline_mode'
(condition (a) 另用同一启动方式重复 3 次)
```

```
TAG=a_fresh_no_e         EXIT=0 crash_hits=0 err_tail=
TAG=b_fresh_with_e       EXIT=0 crash_hits=0 err_tail=
TAG=c_cached_no_e        EXIT=0 crash_hits=0 err_tail=
TAG=d_cached_with_e      EXIT=0 crash_hits=0 err_tail=
TAG=e_rep1_fresh_no_e    EXIT=0 crash_hits=0 err_tail=
TAG=e_rep2_fresh_no_e    EXIT=0 crash_hits=0 err_tail=
TAG=e_rep3_fresh_no_e    EXIT=0 crash_hits=0 err_tail=
PORT_9890= (空)      PID_9877= 127.0.0.1:9877 LISTENING 36392
```

**7/7 `EXIT=0`，`C0000005` / `access violation` / `is_cmdline_mode` 命中 0，stderr 为空**（且这批复核是在两个全量
SCons 构建并发抢 CPU 的条件下跑的，正是报告所称唯一一次异常日志出现的场景）。**撤回成立**，
报告 §9.1 的真实命令与退出码与我的观测一致；报告同时保留了「不带 `--mcp-port` 会优雅尝试绑定 9877」的附注，
我**刻意没有复现该变体**以免触碰用户端口。**未复现崩溃 ⇒ 不推翻撤回，不计缺陷。**

### R4. 其余 AC 的独立重跑（均为我亲自执行的真实输出）

```
[门③ 模块 doctest] bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="[MCPServer]*"
  [doctest] test cases:  73 |  73 passed | 0 failed | 1429 skipped
  [doctest] assertions: 726 | 726 passed | 0 failed |          Status: SUCCESS!   EXIT=0
[门④ 全引擎] bin\...console.exe --headless --test
  [doctest] test cases:   1499 |   1499 passed | 0 failed | 3 skipped
  [doctest] assertions: 425007 | 425007 passed | 0 failed |    Status: SUCCESS!   EXIT=0
[门① 契约子集] check_contract_subset.ps1 -Group project_read_files
  3/3 checks passed   （editor 9888 / game 9889 各 tools=19，本组 6 条 name/description/inputSchema 逐字 True）
  guard_user_port_9877: pid_before=36392 pid_after=36392        GATE1_EXIT=0
[AC-11] python docs\scripts\check_tool_groups.py
  ASSERT every B1 tool appears exactly once: PASS (duplicates=0, missing=0, foreign=0)
  ASSERT every name exists in the 171 entry contract: PASS   ASSERT 41 == 42 - 1: PASS
  BYTES 5441  SHA256 5445d39a117626f8ad001dd588b91c1e15784d53bce4d1ef8595dd72d00e1da9   TOOL-GROUPS CHECK PASS   EXIT=0
[门⑤] accept_m1.ps1 连跑两次： A_EXIT=0 / B_EXIT=0，两次 22/22 cases passed，PASS 清单 Compare-Object 差异 0 行
  case20（A/B 各一份）: tools=19 bytes=5393/5393 byte_identical=True
     sha256_first=sha256_second=768401f893bfa55a7d066cc71dc0edf39b96230138dad5deee1f11d3bffb07b9
  guard_user_port_9877（A/B）: listening=True pid_before=36392 pid_after=36392
```

- **AC-1 / 助手唯一性**：`Select-String` 正向 = `tool_helpers.cpp:40/47/66/174` 4 处定义 + `tool_helpers.h:61/68/73/79`
  4 处声明；`static _join_path|_split_lines|_serialize_variant|_collect_files_by_extension` 反例 **0**；
  旧下划线调用点 **0**；HEAD 测试文件 `SPIKE|print_line` 命中 **0**。
- **AC-2 / 未声明的行为变更**：`git diff 8386726429^..8386726429 -- project_read_{template,analysis}.cpp` 全文我逐段读过，
  只含 **删 4 个助手定义（2 文件共 3 份重复 + analysis 独占 1 份）+ `#include "tool_helpers.h"` + 注释更新 + 9~10 处
  调用点改名**；`--stat` 只含 4 个文件（两个成员文件 + `tool_helpers.{h,cpp}`），**未触碰 `registration.cpp`**，
  故 `tools/list` 的 name/description/inputSchema 不可能因重构改变。`tool_helpers.cpp` 的函数体与我看到的被删
  定义逐字一致（仅去 `static`/去前导 `_`/递归自调用改名）。**无任何工具语义变化。**
- **契约/映射未被改动**：`git log --oneline -- docs/tools_list.renamed.json docs/tool-rename-map.json` → **空**；
  `git diff --stat 8386726429^ HEAD -- <这两文件>` → **空**；两者 sha256 仍为报告 §8 的
  `64723fb9…`（98953 字节）/ `2f552719…`（70917 字节）。
- **AC-5 / 无假通过**：新增 8 个用例（`test_mcp_server.h:2343–2739`）我逐行读过；`skip|SKIP|TODO|FIXME|not available|do not assert`
  在 2340–2745 命中 **0**；三条失败类断言（`-32602` + 逐字 message、`-32001` + `data.suggestion`）真实存在；
  `payload.size()==3`、`has("properties")==false`、`has("lines")==false` 等强断言在位。
- **AC-6 红阶段**：`git ls-tree -r 4b144e6c1d -- modules/mcp_server/tools` 中**无** `project_read_files.*`；
  红树 `registration.cpp` 只有 template/analysis 两行；红树 `tool-groups.json` 的 `project_read_files.implemented=false`
  （HEAD 为 `true`）；红树 75 个 `TEST_CASE`（含 27 处 SPIKE 探针），HEAD 73 个且探针 0 处。失败原因只能是「功能不存在」。
- **AC-10 只读不变式（真机，比 doctest 更强）**：在真实编辑器进程（9888）上，warm-up 让 `.godot` 落定后快照，
  跑完 21 条请求再快照：**39 个文件（含 `.godot/**`）路径+长度+sha256 全部不变，`READONLY_DIFF=0`**。
- **AC-13 端口纪律**：本轮 `netstat` 抽查 10+ 次，9877 始终 `LISTENING 36392`；门① 与门⑤（A/B）分别打印
  `pid_before=36392 pid_after=36392`；收尾 9888–9891 只剩 `TIME_WAIT`，无 `LISTENING`，`godot` 进程只有 36392。
- **AC-12 报告格式**：`## 0. commits / 1. 逐工具表 / 2. 红绿 / 3. 助手唯一性 / 4. 重构等价性 / 5. spike / 6. 五道门 /
  7. 门②三类证据 / 8. 文件指纹 / 9. deviations / 10. blockers / 11. next_step / 12. 复现方法` 全部在位；
  §8 的 12 个文件指纹我用 `Get-FileHash` 全量重算，**12/12 逐字节与报告一致**。

### R5. 对抗性用例（报告 §7 **没有**的用例，全部我自己构造与采集）

工程 `%TEMP%\mcp-t005-acc2\proj`（`.godot/fake.gd`、`.hidden/secret.gd`、`.hiddendir2/b.gd`、`nested/deep/*`、
`scripts/upper.GD`、`nested/deep/d.GDSHADER`、`images/ok.PNG`、`images/icon.svg` 等），`curl.exe --data-binary @file --output <bytes>`：

```
a01 res://scripts/./valid.gd    -> {"path":"res://scripts/valid.gd","size":67}          归一 ✅
a02 res://scripts//valid.gd     -> {"path":"res://scripts/valid.gd",…}                  归一 ✅
a03 res://../secret.gd          -> -32602 "Parameter 'path' must not walk upwards with '..'"  ✅
a04 C:/Windows/win.ini          -> -32602 "Parameter 'path' must address the project ('res://...')" ✅
a05 path:123                    -> -32602 "Parameter 'path' must be a string, got float" ✅
a06 res://scripts（目录）        -> -32001 "File 'res://scripts' not found" + suggestion  ✅（不崩、不写）
a07 max_size:-5                 -> -32602 "must be a positive integer, got -5"           ✅
a08 max_size:0                  -> -32602 "must be a positive integer, got 0"            ✅
a09 max_size:1.5                -> -32602 "Parameter 'max_size' must be an integer, got float" ✅
a10 res://images/ok.PNG         -> {"format":"png","height":8,"width":8,…}（大写扩展名走图片分支）✅
a11 res://images/icon.svg       -> {"format":"png","height":32,"width":32,…}             ✅
a12 project_list_scripts        -> {"count":10,"scripts":[".godot/fake.gd",".hidden/secret.gd",".hiddendir2/b.gd",
                                   "addons/plug/addon_script.gd","nested/deep/c.gd","nested/deep/e.gdshader",
                                   "scripts/broken.gd","scripts/cjk.gd","scripts/valid.gd","shaders/effect.gdshader"]}
                                   -> **只跳过 "."/".."**；`.godot`/`.hidden*`/`addons` 都下钻；`upper.GD` 与
                                      `d.GDSHADER` **不收**（大小写敏感）——与迁移源 `script.rs:54-66` 逐条一致 ✅
a13 read_scene_file_content → .gd（非 .tscn） -> 返回全文 3 键，不校验扩展名（与迁移源一致）✅
a14 read_resource → plain.txt   -> -32001 "Resource '…' not found" + suggestion          ✅
a15 validate_script → upper.GD  -> {"valid":true,"message":"Script compiles successfully"} ✅（真编译）
a16 validate_script → broken.gd -> {"valid":false,"error_text":"ERR_PARSE_ERROR",…}       ✅
a18 read_script → cjk.gd        -> 220 字节响应，`"size":55`（字符数），CRLF 与中文逐字节保真 ✅
a19 list_scripts 带无关参数      -> 正常成功（忽略未知参数，与契约 schema 一致）           ✅
```

### R6. 收尾状态（与开工前逐行一致）

```powershell
git worktree remove --force F:\mcp-t005-acc2-p0 ; git worktree remove --force F:\mcp-t005-acc2-p1 ; git worktree prune
git worktree list  -> F:/RustProjects/godot-mcp-pro/code/godot  c9800ade81 [feature/mcp-server-module]   （只剩主工作树）
Test-Path .git\worktrees -> False    Test-Path F:\mcp-t005-acc2-p0 / -p1 -> False / False
git status --short
  ?? .graphifyignore / ?? build-m0.cmd / ?? graphify-out/ / ?? install-deps-m0.cmd / ?? modules/mcp_server/docs/spec/
netstat: 9877 LISTENING 36392；9888–9891 无 LISTENING（只剩 TIME_WAIT）；godot 进程仅 36392
```

### R7. 本轮判定

| AC | 判定 | 本轮独立依据 |
|---|---|---|
| AC-1 | pass | 4 定义/4 声明/0 反例/0 残留调用点；函数体逐字一致 |
| AC-2 | pass | diff 只含删助手+include+改名；**我重建 8386726429^ 与 8386726429，4229 字节 P0==P1 逐字节相等** |
| AC-3 | pass | 门① 我重跑 3/3 PASS，9888/9889 各 19 工具、6 条逐字 True |
| AC-4 | pass | 活体 `tools/list` 19 条 = `implemented=true` 并集；`check_tool_groups.py` PASS |
| AC-5 | pass | 8 个新用例逐行读；假通过扫描 0；三类错误断言在位 |
| AC-6 | pass | 红树无实现文件/无注册/`implemented=false`/75 例含探针；HEAD 73 例 0 探针 |
| AC-7 | pass | 73 / 726 / 0 failed / EXIT=0（基线 65 / 607） |
| AC-8 | pass | 1499 / 425007 / 0 failed / EXIT=0（基线 1491 / 424888） |
| AC-9 | pass | 我连跑两次 A/B EXIT=0，22/22，PASS 清单差异 0 行 |
| AC-10 | pass | 真机编辑器进程 39 文件全量 sha256 调用前后不变（`READONLY_DIFF=0`） |
| AC-11 | pass | `implemented=true`；`check_tool_groups.py` PASS/EXIT=0 |
| AC-12 | **pass** | §4 已字节保真重采（4229 / `d94a75f3…`），对照点 P1=`8386726429` 判定正确且**经我自建 worktree 复现**；污染根因与算术诚实登记、原始记录未被抹掉、无残留旧值被当有效证据；§8 指纹 12/12 一致 |
| AC-13 | pass | 门① 与门⑤ 均 `pid_before=36392 pid_after=36392`，全程 netstat 一致 |

**第二轮 verdict = `pass`**：第一轮 DEFECT-1（有损采集 + 3411 与事实不符）已由 `3a3c823f26` 用字节保真方式
重采并更正，且**该修复的正确性由我自建 worktree 重建 P0/P1 独立复现**；DEFECT-2 的 `--import` 崩溃主张
在我 7 次复跑中不可复现，**撤回成立**。交付代码、契约逐字、只读性、TDD、五道门、迁移源语义对照**全部成立**。
遗留风险见 R8。

### R8. 本轮遗留风险（不构成 fail）

1. `project_get_resource_preview` 的 `-32001` doctest 未复断言 `data.suggestion`（其余 4 个适用工具都断言了）；
   该字段由共享工厂产出且有框架级 doctest 与真机 curl（我的 `a14/a20` 均含 `data.suggestion`）覆盖。
2. AC-10 的真机不变式我覆盖了编辑器进程（39 文件，含 `.godot/**`）与 doctest 的 11 文件硬断言；
   **游戏进程侧**未做同等的文件快照，仅由「21 例响应 editor==game 逐字节相同」间接支持。
3. `project_validate_script` 的**结构检查降级分支**只在 doctest 进程触发（真实进程语言已初始化）；
   其 `error_text` 固定 `"ERR_PARSE_ERROR"`、message 明说未编译，是设计使然（报告 §9 deviation 4/5/6）。
4. `size` 为**字符数**而非 UTF-8 字节数（我用 `cjk.gd` 复核：磁盘 63 字节、响应 `size=55`），
   与 Rust 迁移源的 `content.len()` 有可见差异，已在报告 §9 deviation 7 登记。
5. 报告 §4.1 的二进制 sha256（P0 `279a05de…` / P1 `9f7147b1…`）与我自建 worktree 的产物不同——
   构建非位可复现（路径/时间戳），报告未主张可复现，**非缺陷**；可复现的是 `tools/list` 字节。
