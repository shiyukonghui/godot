# REPORT-029 — 契约收口：`editor_get_test_report.clear` 的 `default` 与描述（走 override，重生成指纹）

> 任务书：`docs/tasks/TASK-029-clear-default-override.md`；手册：`docs/tasks/PLAYBOOK-group-port.md`（已完整阅读）。
> 先例：`docs/tasks/TASK-024a-e10-play-scene-port.md` + `docs/reports/REPORT-024a-e10-play-scene-port.md`（同一套 override 流程）。
> 分支 `feature/mcp-server-module`；本批**不新增工具**（仍 113/171），**不改任何工具行为**，只改**契约的声明**。

## 0. status / commits

| # | sha | 一行说明 |
|---|---|---|
| 1 | `a7f3e3670a` | `TASK-029: editor_get_test_report declares clear as an opt-in` —— `SCHEMA_OVERRIDES` + `DESCRIPTION_OVERRIDES` + 生成器 1.6.0→1.7.0 + 重生成契约 + 重生成 C++ 注册块 + 关闭过期注释 + 2 个 doctest + 门⑥ pin 行号同步 |
| 2 | `9de513a37f` | `TASK-029: live evidence script for the clear declaration` —— `scripts/mcp029_clear_default_evidence.ps1`（20 条实测） |
| 3 | 本文件所在提交 | `TASK-029 report: REPORT-029 …`（**文档提交，构建不依赖它**；故不在正文引用它自己的 sha） |

`status: **done**`（方案 A 落地；红→绿有真实输出；门 ①–⑥ 全绿；契约与行为在**线上**一致）。

**基线**：开工 HEAD `91df7fd15d`（= 任务书提交）。**门全部绑定在那次构建上**：`scripts/build_local.cmd -Force`（`tests=yes`）
→ `--version` = `4.8.dev.custom_build.91df7fd15` == `git rev-parse --short HEAD`（`91df7fd15d` 的前 9 位），
当时工作树只有 4 个既有的未跟踪物（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`）
加上本批自己的改动。提交 1/2 发生在**全部门跑完之后**：
提交 1 增删的正是门所验证的那批文件（契约/生成器/C++/测试），提交 2 只新增一个**未被编译**的证据脚本 `scripts/*.ps1`。

## 1. 逐工具表

本任务**不新增工具、不改名字、不改组**。唯一被触及的工具：

| new_name | 迁移源（仅类别参考） | 引擎依据（第一参考源） | 自然契约（声明侧的新样子） | C++ 落点 | 与迁移源差异及理由 |
|---|---|---|---|---|---|
| `editor_get_test_report` | `commands/test.rs:561-589`（`cmd_get_test_report`） | 报文本体是 TASK-019/TASK-022 已交付的**文件桥**（`user://mcp_test_report.json`，`tools/tool_helpers.*` 的 `record_test_result` / `load_persisted_test_report_from`）；本任务只动**声明**，用引擎没有任何新 API | `inputSchema.properties.clear = {default: **false**, description: "是否清除结果", type: "boolean"}`；`required: []` 不变；工具 `description` = 原文「获取测试结果报告」+ 追加句（写清缺省纯读、显式 `clear:true` 会删**共享**桥接文件） | 声明侧：`docs/tools_list.renamed.json`（由生成器产出）+ `tools/editor_testing_read.cpp` 的 `// BEGIN generated` 注册块（由 `gen_b2_game_schema.py --in-place` 重生成）；行为侧 `_tool_get_test_report` **一行未改** | 迁移源的 `clear` **声明缺省 `true` 且真的删**：共享文件上「读一次=删一次」正是 M4c 的 G-3。TASK-028 已按「工具真的能用」把行为改成显式 opt-in；本任务把声明对齐到行为（方案 A：**改契约，不改行为**）。`clear` 自身的 `description`（`是否清除结果`）**逐字保留**——破坏性写在工具级描述里，见 §3 |

**为什么这是「契约收口」而不是「行为变更」**：`tools/editor_testing_read.cpp` 里 `_tool_get_test_report` 的
唯一改动是**注释**（把 REPORT-028 里「已上报给决策者、声明与行为暂时不一致」的那两段改成「已由 TASK-029 收口」）。
行为回归（§5）逐条复现 TASK-028 的判据，并给出**更多**证据（响应体 sha256 相同）。

## 2. 红 / 绿（真实输出）

新增两个 doctest（`tests/test_mcp_server.h`，命名空间 `Task029`）：

1. `[MCPServer] TASK-029: editor_get_test_report declares clear as an opt-in` —— 从**注册表**（= 线上 `tools/list` 的来源）
   读该工具的 `description`/`inputSchema`，断言 `clear.default == false`、`type/description/required` 逐字未动、
   描述是**追加**（原文仍是前缀）、并出现 `共享`/`user://mcp_test_report.json`/`clear:true`/`clear:false`。
2. `[MCPServer] TASK-029: an omitted clear is a pure read, and clear:true is the only delete` —— 声明只有与运行时一致才有意义：
   两次缺省读都拿到完整报告、`cleared` 为空、桥接文件仍在；显式 `clear:true` 才删，且 `cleared` 列出两半。

**红**（契约还没改时，`build_local.cmd -Force` 后 `--headless --test --test-case="*TASK-029*"`；log sha256 `86c3f0f5…`）：

```
.\modules/mcp_server/tests/test_mcp_server.h(15600): ERROR: CHECK( (bool)clear["default"] == false ) is NOT correct!
  values: CHECK( true == false )
...(15614) description.begins_with(original_description + " ")  -> CHECK( false )
...(15615) description.contains(shared_word)                   -> CHECK( false )
...(15616) description.contains("user://mcp_test_report.json")  -> CHECK( false )
...(15617) description.contains("clear:true")                   -> CHECK( false )
...(15618) description.contains("clear:false")                  -> CHECK( false )
[doctest] test cases:  2 |  1 passed | 1 failed | 1646 skipped
[doctest] assertions: 28 | 22 passed | 6 failed |
[doctest] Status: FAILURE!            （exit 1）
```

**绿**（override + 重生成契约 + 重生成 C++ 注册块 + `build_local.cmd -Force` 之后；log sha256 `bdf5b825…`）：

```
[doctest] test cases:  2 |  2 passed | 0 failed | 1646 skipped
[doctest] assertions: 28 | 28 passed | 0 failed |
[doctest] Status: SUCCESS!            （exit 0）
```

**红阶段真的抓到东西，而且抓到了我自己**：第一版用例把中文期望值写成**源码字面量**
（`CHECK(String(clear["description"]) == "是否清除结果")`），在 `build_local.cmd -Force` 后报
`values: CHECK( 是否清除结果 == 是否清除结果 )` —— 两边**打印完全一样却不等**。原因是
`tests/test_mcp_server.h` **没有 BOM、编译时不带 `/utf-8`**，非 ASCII 字面量的含义取决于编译器对源字符集的映射。
测试随即改成 `String::utf8("\xe8\x8e\xb7…")` 形式的**显式 UTF-8 字节转义**（并写进注释），断言对象变成「契约逐字携带的字节」，
与构建环境的区域设置无关。这是一处 **deviation**（§8 第 5 条），也是 PLAYBOOK §7.5 那条教训的第五个实例。

## 3. 契约变更（只走 override，未手改契约文件）

### 3.1 生成器（`scripts/gen_renamed_contract.py`）

* `GENERATOR_VERSION` `1.6.0` → **`1.7.0`**，docstring 新增 **v1.7** 段（机制说明 + 为什么这是**第三个** schema override、
  为什么它与 description override 成对）。
* 新增 `DESCRIPTION_OVERRIDES["get_test_report"]`（**append** 模式）。
* 新增 `SCHEMA_OVERRIDES["get_test_report"]`（**`mode: "replace"`**）。

**override 的 `reason` 原文（逐字，取自 `_meta.overrides`）**：

`description / get_test_report / append`：

```
TASK-029 契约与行为一致（TASK-028 G-3 收口，决策者裁决方案 A）：原文只有“获取测试结果报告”，既没说清 clear 的缺省语义，也没说清它会删掉一个**共享**文件。而读取带破坏性副作用是有实测记录的缺陷（user://mcp_test_report.json 由同一编辑器进程的所有客户端共用，先读的一方会删掉后读一方还没读的报告，M4c 的 G-3）；TASK-028 已把实现改成显式 opt-in，契约是唯一还在宣称“缺省即清”的地方。一个只读 tools/list 的智能体必须能看出这一点，故追加判别句。原文“获取测试结果报告”逐字保留在句首（append 模式）。
```

`inputSchema / get_test_report / replace`：

```
TASK-029 契约与行为一致（TASK-028 G-3 收口，决策者裁决方案 A）：把 clear 的 default 由 true 改为 false。被替换的成员逐字为 "default": true；被移除的 required 成员逐字为 []（该 schema 本来就没有必填参数，“移除”的是一个空列表）；clear 的 description（"是否清除结果"）与两个 type 成员一字未动，properties 只此一个成员。TASK-028 的实现已是显式 opt-in（缺省或 false = 纯读、不删共享桥接文件），契约是唯一还在宣称“缺省即清”的地方。
```

两条硬性要求都**可机器核对**（`scripts/tests` 之外的自证脚本输出，见 §4）：

* `reason` 里逐字含被替换的成员 `"default": true`（任务书 §1.1 的要求）→ `True`；
* v1.5 守卫要求 `reason` 逐字引用被移除的 `required` 成员 `[]` → 生成器守卫通过（否则 `SystemExit`）。

**新 `clear` 对象**（与旧值逐字段对照）：

| 字段 | 旧 | 新 |
|---|---|---|
| `clear.default` | `true` | **`false`** |
| `clear.description` | `是否清除结果` | `是否清除结果`（**逐字未动**） |
| `clear.type` | `boolean` | `boolean`（未动） |
| `inputSchema.required` | `[]` | `[]`（未动） |
| `inputSchema.type` | `object` | `object`（未动） |
| 工具 `description` | `获取测试结果报告` | 原文 + 追加句（原文仍是前缀） |

### 3.2 重生成与指纹

```
python modules/mcp_server/scripts/gen_renamed_contract.py     → exit 0
  output tools = 171 ; overrides = 13
  description/get_test_report:append, inputSchema/get_test_report:replace （新增两条）
  output sha256 = 4492a0f7bbfc9785a84abeff65ff87b8032d8d14770922f061335ba9fea77535
python modules/mcp_server/scripts/gen_b2_game_schema.py --group editor_testing_read --in-place tools/editor_testing_read.cpp  → exit 0
  再跑一次：`the generated span … is already up to date`（幂等，第二次 0 字节变化）
```

* 契约**不是手改的**：`docs/tools_list.renamed.json` 的 sha256 由 `c5120948…54fc6` → **`4492a0f7…77535`**，
  文件 104869 B（生成器自报的 `output sha256` 与文件指纹一致，说明「写盘的内容 == 自检的内容」）。
* 指纹更新面：`_meta.generator_version` `1.6.0`→`1.7.0`、`_meta.overrides` +2 条；
  `_meta.generated_from_sha256`（旧契约冻结值 `8f8051c4…`）与 `_meta.map_sha256`（`2f552719…`）**未变**（映射未动）。
* C++ 注册块随之更新：`v1["default"] = false`，`description` 变成新文本（`String::utf8(...)` 逐字）。

### 3.3 `TOOL-NAMING.md` —— **证明**无需重渲染，而不是声称

`docs/TOOL-NAMING.md` 由 `docs/scripts/gen_table.py` 从 **`tool-rename-map.json`** 渲染（**不读契约**），本批没动映射：

```
python modules/mcp_server/docs/scripts/gen_table.py --check-only   → exit 0
  DETERMINISM  render run#1 == render run#2 byte-identical (95673 bytes): PASS
  CHECK-ONLY: document not written.
sha256(docs/TOOL-NAMING.md) = ce9bc325699cae6cfaec104d1e3477e91d78a5440f8893366cc030c03c36c975
  —— 与 REPORT-024a 记录的 `CE9BC325…` 逐字节相同（未改）
```

## 4. 契约结构化 diff（机器输出：**只动目标字段 + `_meta`**）

自证脚本 `%TEMP%\task029_contract_diff.py`（只读：`git show HEAD:` 与工作树两份 JSON 逐工具、逐字段比较）：

```
tools in HEAD   : 171
tools in worktree: 171
names added/removed: [] []
changed tools   : 1
  - editor_get_test_report: description, inputSchema.properties.clear.default
untouched tools : 170 / 171
_meta keys added/removed: [] []
_meta.generator_version: '1.6.0' -> '1.7.0'
_meta.overrides: +2/-0 records; added kinds=[('description', 'get_test_report', 'append'), ('inputSchema', 'get_test_report', 'replace')]
_meta.overrides: removed = []
description override is append-only (old wording kept as prefix): True
schema reason quotes the replaced member ("default": true): True
schema reason quotes the removed required member ([]): True
```

`git diff --numstat`（**15 insertions / 3 deletions**，全部落在上面这几处）：

```
15  3   modules/mcp_server/docs/tools_list.renamed.json
```

## 5. 行为回归（全部实测，`scripts/mcp029_clear_default_evidence.ps1`，**20/20 PASS，exit 0**）

脚本：`scripts/mcp029_clear_default_evidence.ps1`；证据目录 `%TEMP%\task029-clear-default\evidence\`（每个响应体落盘 + sha256）；
log sha256 `02461eb9…`。请求体一律 `ConvertTo-Json` → `Write-McpUtf8NoBom` → `curl.exe --data-binary @file`；
响应体一律 `curl.exe -s -o <file>`（PLAYBOOK §7.1）。

| 检查 | 实测 |
|---|---|
| `port_9877_owner_before` / `_after` | pid `36392` / `36392`（用户 Godot 4.7.1-mono，**全程只读**） |
| `port_9888_free` / `port_9889_free` | 开工前无人监听 |
| `scratch_project_imported` | `--import` exit 0（走共享 `Import-McpProject`，无 BOM） |
| `tools_list_has_the_tool` | 9888 上 `tools/list` 共 **91** 条，找到 `editor_get_test_report` |
| **`wire_clear_default_is_false`** | **线上** `inputSchema.properties.clear.default = false`（`Boolean`）——**解析响应体**得到，不是读文件 |
| `wire_clear_description_kept` | 线上 `clear.description = 是否清除结果`（== 冻结旧契约的值：`True`） |
| `wire_description_names_shared_file` | 描述以旧原文开头（append）且含 `共享` / `user://mcp_test_report.json` / `clear:true` / `clear:false` |
| `contract_file_agrees_with_wire` | 契约文件 `clear.default = false`，且线上描述**逐字等于**契约描述 |
| `game_assertions_recorded` | 游戏进程写两次断言：`pass=True fail=False`，桥接文件已生成 |

### 5.1 缺省 → 纯读；两个客户端 → **响应体 sha256 相同**

| 客户端 | 请求 | 响应要点 | 响应体 sha256 / 字节 |
|---|---|---|---|
| A | `editor_get_test_report {}`（**没有** `clear`） | `total=2 passed=1 failed=1 source=game_process_file cleared=[] report_file_present=true`，文件仍在 | `df6c04062a8edc36bfff08792c7a1fd18c58ede7af68b370f1de9434fe9458df` / **914 B** |
| B | 同上（第二个客户端） | 同上；文件仍在 | **同一个** `df6c0406…458df` / 914 B |
| C | `editor_get_test_report {"clear": false}` | 同上，`cleared=[]`，文件仍在 | 仍**同一个** `df6c0406…458df` / 914 B |

（A/B/C 的 JSON-RPC `id` 同为 `1`：比较的对象是**响应体**，任何「合法但会变」的字段都会掩盖报告本身的变化。）

**这是本任务要求的「非破坏性双客户端证据」**：两次纯读的响应体**逐字节相同**——
不是「字段看起来一样」，而是 sha256 相等；桥接文件在 A、B、C 三次读之后都存在。

### 5.2 显式 `clear:true` → 才清；随后是**诚实空**

| 请求 | 响应要点 | sha256 / 字节 |
|---|---|---|
| `editor_get_test_report {"clear": true}` | `total=2`（**清之前的**报告如实返回），`cleared=["editor_process","game_process_file"]`，文件**已消失** | `3233b99c80dda60b1ddee31ec9145d2db4eb0de9c88947d1ab31fcb8bb93706d` / 954 B |
| 再读 `{}` | `total=0 no_results=true pass_rate="N/A" all_passed=false report_file_present=false details=[] source=editor_process`，`report_unavailable_reason="'user://mcp_test_report.json' does not exist"` | `4422258215a9dee3fe1108cfbde42a8efb1f067fb484c8c1e9274283f98a11b5` / 392 B |

**没有伪造 `total`**：空报告不是「全绿」，`all_passed=false`、`pass_rate=N/A`、`no_results=true`，并**指名**为什么空。

### 5.3 回归：TASK-028 的证据脚本重跑（确认未回退）

```
powershell -File modules/mcp_server/scripts/mcp028_subpaths_clear_import_evidence.ps1  → exit 0
  TASK-028 evidence: 27 checks, 0 failed      （log sha256 0e94010a…）
  其中 G-3 段：A/B 两次纯读 `cleared=[]` 且文件仍在；显式 clear 后 `cleared=["editor_process","game_process_file"]`、文件消失、再读 `total=0 no_results=true`
```

## 6. 门（全部自己跑，贴真实输出与退出码）

| 门 | 命令 | 结果 |
|---|---|---|
| 0 绑定构建 | `modules\mcp_server\scripts\build_local.cmd -Force`（`tests=yes`） | 每次改动后重建，exit 0；跑门时 `--version` = `4.8.dev.custom_build.91df7fd15` == `git rev-parse --short HEAD`（`91df7fd15d`） |
| ① 契约子集逐字 | `scripts\check_contract_subset.ps1 -Group editor_testing_read` | **exit 0，3/3 checks passed**：`editor_9888_contract_subset`（91 条）里 `editor_get_test_report: name=True description=True inputSchema=True`；`game_9889_contract_subset`（53 条）里 `correctly absent on the game endpoint`；`guard_user_port_9877` 前后同 pid。log sha256 `a39477b1…` |
| ② 三类证据 + 活证据链 | `scripts\mcp029_clear_default_evidence.ps1` | **exit 0，20/20 PASS**（§5；响应体全落盘 + sha256） |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | `test cases: 219 \| 219 passed \| 0 failed`，`assertions: 8443 \| 8443 passed \| 0 failed`，exit 0（基线 REPORT-028 217/8415 → **+2 例 / +28 断言**，passed 只增不减）。log sha256 `671ca9a4…` |
| ④ 全引擎回归 | `--headless --test` | `test cases: 1645 \| 1645 passed \| 0 failed \| 3 skipped`，`assertions: 432725 \| 432725 passed \| 0 failed`，exit 0（基线 1643/432697 → +2/+28）。log sha256 `5730ae57…` |
| ⑤ 批收口 | `scripts\accept_m1.ps1` **连跑两次** | run1 exit 0 **22/22**（log sha256 `722cddcb…`）、run2 exit 0 **22/22**（`f60c87d1…`）；PASS 清单 `Compare-Object` **无差异**（`identical=True`）；`implemented tools = 91(editor)/53(game)`，`contract = 171`；`guard_user_port_9877` 两次都 PASS |
| ⑥ 收窄点清单 | `python scripts\check_narrowing_points.py` | **exit 0**：`scanned 30 / pinned 30`，**无 drifted 条目**（本批把 `tools/editor_testing_read.cpp` 的两个 pin 由 439/442 同步到 445/448）。本次**未新增**任何收窄点 |
| — 回归：TASK-028 证据脚本 | `scripts\mcp028_subpaths_clear_import_evidence.ps1` | **exit 0，27/27**（§5.3） |
| — `TOOL-NAMING.md` 无需重渲染 | `gen_table.py --check-only` | exit 0，`DETERMINISM … byte-identical (95673 bytes): PASS`（§3.3） |
| — 映射/契约自检 | `check_rename_map.py` | `RESULT: PASS (all checks green)`，exit 0；契约 171 条，`G5 171 == 174-2-1` |

**端口纪律**：全程未占用/未杀/未重启 **9877**（每个起引擎的脚本都记录前后 pid 相同：`36392`）；测试只用 9888/9889；
scratch 全在 `%TEMP%`；**未 push**。

## 7. 本批改动文件与 sha256

| 文件 | 字节 | sha256 |
|---|---|---|
| `docs/tools_list.renamed.json`（**已改**，生成器产出） | 104869 | `4492a0f7bbfc9785a84abeff65ff87b8032d8d14770922f061335ba9fea77535` |
| `scripts/gen_renamed_contract.py`（**已改**，1.7.0） | 40651 | `34a9ef2ee36147c720bc121c0f6bc268a03ff0b42c7bc79b5c684d36b637b2d4` |
| `tools/editor_testing_read.cpp`（**已改**：注册块 + 注释） | 27114 | `15e483b3747816570878f4745dd0db15152bb1ae19f81069bddf5205a3a6633d` |
| `tests/test_mcp_server.h`（**已改**：`Task029` 两例） | 683591 | `a84c68778f3edcd3b06cdd946c36dfe15e1d4819b8a11d3403d337bf28be9ea7` |
| `scripts/check_narrowing_points.py`（**已改**：两个 pin 行号） | 23278 | `2f2931bf4f5dbb95dd6dcbe22ebc8038fd82c2fb2aaa8a9cae6a76013538a5b3` |
| `scripts/mcp029_clear_default_evidence.ps1`（**新增**） | 21337 | `b48355dc402e2992b5b231d8215308536cb9d95ab749c5e9645466c1d1d9f343` |
| `docs/TOOL-NAMING.md`（**未改**） | 98720 | `ce9bc325699cae6cfaec104d1e3477e91d78a5440f8893366cc030c03c36c975` |
| `docs/tool-rename-map.json`（**未改**） | 70917 | `2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd` |
| `scripts/gen_b2_game_schema.py`（**未改**，仅被调用） | — | 未被触碰（`git status` 无它） |

契约/映射/五份 group manifest 之外，**没有任何工具文件被改动**（`git diff --numstat` 只有 §4 那一行契约 + 4 个脚本/测试文件）。

## 8. deviations（逐条显式列出）

1. **没有改 `DESIGN-DETAIL.md` / 任何规范文档**：PLAYBOOK §7.2 与任务书都要求「规范由决策者维护；实现者只写报告」。
   本批的正规落点是 `docs/tasks/PLAYBOOK-group-port.md` 之外无。若决策者希望把「override 的 `reason` 必须逐字引用
   被改动的**非 `required`** 成员」升级为生成器守卫（现在只是本批自己遵守的约定），那应是下一批的规范动作。
2. **`TOOL-NAMING.md` 未重新渲染**：它从 `tool-rename-map.json` 渲染而非从契约渲染，映射未动，
   已用 `gen_table.py --check-only`（exit 0、两次渲染 byte-identical、文件 sha256 与 REPORT-024a 记录**逐字节相同**）
   机器证明是空操作，而不是只在报告里声称。任务书 §1.5 说「用 `--check-only` **证明**」，正是这一条。
3. **`GENERATOR_VERSION` 1.6.0 → 1.7.0**：任务书没有明文要求 bump，但 v1.5/v1.6 的先例是「契约内容变化必伴随版本变化」
   （它是 `_meta` 里唯一的生成器指纹）；不 bump 会让两次内容不同的契约共享同一个版本号。
4. **`check_narrowing_points.py` 的两个 pin 行号 439/442 → 445/448**：TASK-029 在该文件上方加了 6 行注释导致漂移。
   门⑥ 本来自带「行号漂移不算失败」的说明（identity index），但 REPORT-028 已确立「把清单保持精确更省下一次误判」的惯例。
   **收窄点本身一个都没有新增/移动**（`scanned 30 / pinned 30`）。
5. **`Task029` 的中文期望值用显式 UTF-8 字节转义**：`tests/test_mcp_server.h` 无 BOM 且编译不带 `/utf-8`，
   直写字面量会得到「打印相同却不相等」的字符串（红阶段实测）。改用 `String::utf8("\xe8\x8e\xb7…")` 后，
   断言对象变成契约逐字携带的字节。这是**测试写法**的偏离，不是产品行为。
6. **证据脚本是纯 ASCII（0 个非 ASCII 字节）**：Windows PowerShell 5.1 以 ANSI 代码页（本机 `gb2312`）读取**无 BOM** 的 `.ps1`，
   中文常量会被静默损坏（本仓库 32 个 `.ps1` 全部是 ASCII，故无先例可循）。脚本里两个中文串分别来自
   `-join ([char]0x5171, [char]0x4EAB)`（`共享`）与**冻结旧契约**（`F:\moonbit-hof-rs\tests\fixtures\mcp\tools_list.json`，
   用 `[IO.File]::ReadAllText(..., [Text.Encoding]::UTF8)` 显式解码）——后者同时给出「append-only：原文仍是前缀」的机器判据。
7. **`clear` 自身的 `description` 未改**（保持 `是否清除结果`）：任务书 §1.1 要求「其余成员（`type` 等）**逐字保留**」，
   所以「删的是共享文件」写在**工具级描述**的追加句里（§3.1），schema 里因此只有**一个**字段的**一个值**发生变化。
8. **报告提交发生在门之后**：提交 1/2 只含非编译输入与已编译输入的内容本身，门跑在「已含全部编译改动」的二进制上
   （`--version` == `91df7fd15d` == 当时的 HEAD）。本报告提交是纯文档，构建不依赖它（与 REPORT-024a/028 的处理一致）。

## 9. blockers

**无**。（9877 全程只读；未 push；无环境阻塞；`--import` 走共享守卫，本批 3 次导入全部一次 exit 0。）

## 10. next_step_recommendation

1. 交给**全新**验收子代理独立验收。建议它自己复核：(a) 只读一次 `tools/list` 就确认 `default=false` 与描述
   （`docs/tools_list.renamed.json` 与 9888 线上都应一致）；(b) 重跑 `scripts/mcp029_clear_default_evidence.ps1`
   验证 `two_plain_reads_are_byte_identical`（两次纯读的响应体 sha256 相同）无法被「看起来一样」蒙混；
   (c) 用 `git show HEAD:` 与工作树做**自己的**结构化 diff，确认 170 条工具未被触碰。
2. 仍待决策者落笔的**非本任务**事项（REPORT-028 §7 的另一半）：是否把 `--import` 的 `0xC0000005`
   上游材料提给 Godot 上游（本批未涉及，也未修改引擎代码）。
3. 剩余 **58 个未实现工具**（113/171）按既有批次继续；本批证明「契约与行为不一致」这类缺陷可以
   用「override + 重生成 + 全指纹 + 线上逐字门」在**不碰行为**的前提下收口，建议后续遇到同类不一致直接复用这条路径。
