# REPORT-AUDIT-002 — 独立验收：B1 框架 + 6 工具模板组 + 全 B1 组清单 + 映射 v1.2

- **任务书**：`docs/tasks/TASK-AUDIT-002-b1-framework.md`（唯一的验收来源；本报告的自包含依据）
- **验收方独立性**：本报告由**未参与实现**的独立验收方产出。`docs/reports/REPORT-002-b1-framework.md`
  只被当作「被检验的主张清单」使用，其中每一条都在本报告里用**我自己复现**的命令输出或**我自己读到的源码行**重新判定；
  凡是我没有独立复现的，明确写 `unconfirmed`。
- **工作目录**：`F:\RustProjects\godot-mcp-pro\code\godot`（分支 `feature/mcp-server-module`，HEAD `74d565f24d`）
- **验收时工作树**：`git status --porcelain` 只有 4 条与本任务无关的未跟踪项
  （`.graphifyignore` / `build-m0.cmd` / `graphify-out/` / `install-deps-m0.cmd`），**无 M 条目**。
- **9877 纪律**：验收全程 `127.0.0.1:9877` 始终是用户进程 `PID 36392`（`netstat -ano` 实测；accept_m1 与
  check_contract_subset 两次自跑均打印 `pid_before=36392 pid_after=36392`）。本验收只使用 9888/9889。

---

## 0. verdict

| 维度 | 判定 | 依据 |
|---|---|---|
| **机械层**（哈希 / 字节数 / 条数 / 清单 / 脚本门） | **pass** | §3.4.13、§3.1.2/3、§3.4.14 |
| **行为层**（6 工具真实输出与契约、参数校验、路径安全、两个取消合并工具的差异） | **pass（含 D-2/D-4 两个 non-blocking 缺陷）** | §3.3.9–12、§3.2.6–8 |
| **框架层**（ToolBuilder 强制声明、编辑器守卫、单入口注册） | **pass**（ToolBuilder 拒绝行为**已实测**，见附录 A-M1） | §3.2.4–8 |
| **工程门**（doctest / 全引擎 / accept×2 / 契约子集门 ×2 端点） | **pass** | §3.4.14 |
| **实现方 9 条 deviations** | **8 条建议接受；1 条（deviation 8）仅需改写过时文字；另在 D-1 里提出一条超出 9 条范围、需裁决的顺序语义问题** | §3.5 |

**总判定：`pass`（不阻塞），带 5 个非阻塞缺陷（severity: 3×minor + 2×nit）与 1 条架构建议。**

**`verdict_scope`（本判定的作用范围，逐条限定）**：

- **覆盖**：B1 框架（`tools/registration.{h,cpp}`、`tools/tool_builder.{h,cpp}`、`tool_registry.{h,cpp}`
  在 GDR-16/17/18 相关面）、模板组 6 个工具（`tools/project_read_template.{h,cpp}`）、
  `docs/tool-groups.json`（41 工具 / 7 组）、`docs/tools_list.renamed.json` v1.2（171 条）、
  `docs/TOOL-NAMING.md`（174 行对照表）、本轮改动的两个脚本（`accept_m1.ps1` 的 SUMMARY 面、
  `check_contract_subset.ps1` 的执行结果）。
- **不覆盖（明确排除）**：B1 其余 6 组（`project_read_analysis`、`project_read_files`、
  `project_write_resource_scene`、`editor_read_scene_inspector`、`editor_write_scene_editor`、
  `running_game_read_scene`）的**实现**——它们尚不存在，本判定只核对它们的**清单正确性**；
  也不覆盖 B2–B5、hof-rs 侧、`godot_mcp_gdext` 侧、以及引擎其它目录。
- **判定基准**：验收时 HEAD = `74d565f24d`，工作树无 `M`；若之后任何被验收文件发生变化，
  本判定的机械层结论（哈希/字节数）自动失效。
- **强度**：机械层与工程门是**我本机自跑**的完整结果；行为层是**我自造工程 + 我自造反例**的实况响应；
  框架层的 ToolBuilder 拒绝是**我自造违规用例 + 独立副本重建**的实测；
  路径安全是**我自造 22 条反例**的实测（未找到逃逸）。

**5 个缺陷没有一个是行为错误**：都是「说辞 vs 实测」或「机械污染」，不改变任何工具的成功/失败语义。
按上一轮（TASK-AUDIT-001）的口径，它们属于必须登记、但不阻塞 pass 的等级。**唯一需要决策者裁决的**是
**D-1（`tools/list` 顺序与 v1.2 契约不同）**：当前所有门都是**集合等价**（不比较顺序），
所以它没被任何门抓住；请见 §4 D-1 的裁决请求。

---

## 1. 我实际执行的命令（可复现锚点）

| # | 命令 | 用途 |
|---|---|---|
| E1 | `sha256sum docs/{tools_list.renamed.json,TOOL-NAMING.md,tool-groups.json,tool-rename-map.json}` + `stat -c %s` | 机械指纹（§3.1.2） |
| E2 | `./bin/godot...console.exe --headless --test --test-case="[MCPServer]*"` | doctest 53/53（§3.4.14） |
| E3 | `./bin/godot...console.exe --headless --test` | 全引擎 1479/0/3（§3.4.14） |
| E4 | `powershell -File modules/mcp_server/scripts/accept_m1.ps1` ×2 | 工程门 21/21 ×2（§3.4.14） |
| E5 | `powershell -File modules/mcp_server/scripts/check_contract_subset.ps1 -Group project_read_template` | 9888+9889 逐字 6/6（§3.4.14） |
| E6 | `curl.exe -sS -X POST http://127.0.0.1:9888/mcp -H 'Content-Type: application/json' --data-binary @<file>` | 行为层三类证据（§3.3.12） |
| E7 | `py -3 %TEMP%\audit002\{a4_naming,a5_xcheck,c1_groups,c2_b1,c3_verbs,c5_overrides,b6_trav}.py` | 我自写的重算脚本（不使用被验收脚本） |
| E8 | `git merge-file -p agentA base agentB`（全部在 `%TEMP%\audit002\merge`） | 并行安全实证（§3.4.15） |
| E9 | `%TEMP%\audit002\tree` 引擎树副本 + 注入违规用例 + `scons` 重建 | ToolBuilder 违规实测（§3.2.5） |

**环境事实（自己实测，不采信报告）**：`godot.windows.editor.x86_64.console.exe` 报告的版本是
`Godot Engine v4.8.dev.custom_build.1090d0480`（**不是** 4.7.1-mono）；用户 9877 上是另一份
`Godot_v4.7.1-stable_mono`，两者互不影响。所有临时脚本与所有生成物都在
`C:\Users\wyl\AppData\Local\Temp\audit002\**`（下称 `%A2%`）。

---

## 2. 验收对象机械指纹（§3.1.2 的一部分）

| 文件 | 实现方声称 | 我实测 | 判定 |
|---|---|---|---|
| `docs/tools_list.renamed.json` | 98923 B / `898d8682…d57b` / 171 条 | 98923 B / `898d868278147cb6f11e83fe11e4e065fb9aa66d13b0a801d81a89354618d57b` / 171 条 | **一致** |
| `docs/TOOL-NAMING.md` | 98462 B / `f68f1551…1d59` | 98462 B / `f68f1551dc01a72331ae9b1590a8ed9167102c10a947a8f1607bfae0b2561d59` | **一致** |
| `docs/tool-groups.json` | 5443 B / `9644911a…0e59` / 41 工具 7 组 | 5443 B / `9644911a01e983e69074b7988462789388e2dc59e17c74308fabb368d2ab0e59` / 41 工具 7 组 | **一致** |
| `docs/tool-rename-map.json` | 未改动 / 70917 B / `2f552719…` | 70917 B / `2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd`（= 契约 `_meta.map_sha256`） | **一致** |
| 契约源 fixture（只读） | `_meta.generated_from_sha256` = `8f8051c4…` | 原 fixture 48749 B / `8f8051c4c0f8941089f0b21a193cef7c51fa7c41d7e312b1463ea8593f313c54` | **一致** |

---

## 3. 必须核实的 15 项：逐条结论

### 3.1 预备项

#### 3.1.1 七条 description 判别点 —— 存在且**逐条对回迁移源码为真**

契约里 7 条 description 我都取了出来（`%A2%\seven.txt`），并逐条读迁移源核对。**7/7 为真，没有编造**：

| 新名 | 契约内联判别点（节选） | 我读到的源码证据 | 判定 |
|---|---|---|---|
| `editor_analyze_signal_flow` | 按节点嵌套 `nodes[]`、只统计持久连接（`flags & 1`）、`node_path` 精确 | `analysis.rs:387-410`（`nodes_data`/`total_nodes`）；`analysis.rs:115-116` `var flags = c.get('flags', 0); if int(flags) & 1 == 0: continue;`；`analysis.rs:399` `if !root.has_node(&node_filter)` = 精确匹配 | **真** |
| `editor_list_signal_connections` | 扁平 `connections[]`、收全部连接、`node_path`/`signal_name` 子串 | `batch.rs:207-234` 起手就是 `var connections = []`；过滤用 `contains`（子串）；无 `flags` 过滤 | **真** |
| `project_search_file_names` | 只匹配文件名子串、大小写不敏感、上限 200、不读内容不返回行号 | `project.rs:159-182` push 的是 `full`（文件路径字符串）；`175` `f.to_lowercase().contains(&query.to_lowercase())`；`project.rs:189` `search_files_recursive(..., 200)` | **真** |
| `project_search_file_contents` | 逐行 `{file,line,text}`、大小写不敏感、上限 50、跳过 `addons`/`.godot` | `project.rs:221-229`（`file`/`line`/`text`= `line.trim()`）；`223` `to_lowercase().contains`；`208` 跳过 `addons`/`.godot`；`244` `..., 50)` | **真** |
| `project_find_files_referencing_symbol` | 按文件聚合 `{file,lines[]}`、每文件 ≤5 行、大小写敏感、上限 100、跳过隐藏与 `addons`、只扫 4 种后缀 | `batch.rs:474-488`（`content.contains(pattern)` = 大小写敏感；`{file,lines}`）；`477-484` `line_matches.len() >= 5` 即 break；`444` `starts_with('.')` 跳过隐藏；`457` 跳过 `addons`；`461-464` 四种后缀 | **真** |
| `project_convert_uid_to_path` | 入参文本 UID、出参 `{uid,path}`、UID 文本非法即参数错误 | `project.rs:295-305`：`text_to_id` 失败（`-1`）→ `Err(McpError::invalid_params(...))`；成功 `{uid, path}` | **真** |
| `project_convert_path_to_uid` | 入参项目路径、出参 `{path,uid}`、路径未注册时 `uid=""` 且不报错 | `project.rs:308-321`：任何失败路径都 `Ok({"path": path, "uid": ""})` | **真** |

**「只看名字 + description，一个智能体能否可靠二选一」——我的独立裁决（逐对）**：

| 对 | 裁决 | 理由（我的判读） |
|---|---|---|
| `editor_analyze_signal_flow` ⇄ `editor_list_signal_connections` | **够** | description 把三条决定性差异都写了：返回形状（嵌套 vs 扁平）、持久连接过滤（`flags & 1` vs 全部）、匹配方式（精确 vs 子串）；两侧还互指对方名字。名字本身（`analyze` vs `list`）也已经是动词闭集里的语义区分。 |
| `project_search_file_names` ⇄ `project_search_file_contents` | **够** | 「只匹配文件名 / 不读内容」vs「逐行 `{file,line,text}`」是硬判据；两者互指。这一对**光看名字其实也接近可判**（`file_names` vs `file_contents`），description 把上限（200/50）与大小写（不敏感/不敏感）说清了。 |
| `project_search_file_contents` ⇄ `project_find_files_referencing_symbol` | **够（但描述里有一处文字不稳定，见 D-2）** | 形状（逐行 vs 聚合）、大小写（不敏感 vs 敏感）、上限（50 vs 100）三项都在。这是最关键、也最容易混的一对：description 的三项差异**与我实测的行为完全一致**（§3.3.10）。 |
| `project_convert_uid_to_path` ⇄ `project_convert_path_to_uid` | **够** | 入参类型（UID 文本 vs 项目路径）、出参字段序（`{uid,path}` vs `{path,uid}`）、错误语义（非法即报错 vs 未注册不报错）三点齐全；两侧互指。 |

**补充裁决（我自己的对抗性判读）**：这 7 条的判别点全部是**可机检的行为事实**（形状/上限/大小写/过滤规则），
不是形容词。唯一一个「措辞不精确」的是 `project_search_file_contents` 描述里把另一侧写成
「要按文件聚合的 {file,lines[]}（大小写敏感、上限 100）」——**这三项都对**，问题不在这里；
问题在实现方报告里对**同一输入**的命中数说法（D-2）。

#### 3.1.2 nit N-1 —— `disposition` 纯枚举 / 174 行 0 不一致 / 头部指纹

**我自写脚本重算（`%A2%\a4_naming.py`，不使用 `docs/scripts/gen_table.py`），结论：**

- **N-1 已闭合**：第 2 节四张表（103+24+45+2）**恰好 174 个数据行**；
  逐行 9 列（`old_name|channel|verb|object|new_name|mutating|scope|disposition|reason`）与
  `tool-rename-map.json` **逐字段比对 = 174/174，0 不一致**；
  `disposition` 单元格**全部是纯枚举且包在反引号里**（`impure disposition cells: 0`）；
  `new_name` 唯一重名组只有 `editor_get_performance_monitors`（= 那一对 `merge_into`）。
- **头部指纹与新契约/映射一致**：头部 `tool-rename-map.json` 的
  `70917 B / 2f552719…9c2bd / 174 → 171` 三项与实测一致；`_meta.map_sha256` 也与之一致。
  注意：`TOOL-NAMING.md` 头部**没有**（也不需要）引用 `tools_list.renamed.json`——
  它是**映射 v1.1 的对照表**（174 行），契约 v1.2 是它的派生物；头部把 `171` 与
  `174 − 2 下架 − 1 合并` 写清了。我判定「头部指纹与新契约一致」成立。
- **我自己发现的 nit（D-5）**：`get_project_info` 那一行的 `reason` 单元格里有一个**未转义的 `|`**
  （`... EditorInterface.get_base_control().get_size()）|project.rs:80-97）...`）。
  地图 `reason` 里含 1 个裸 `|`，渲染时没有 `\|` 转义 → 一个天真的「按 `|` 切 9 列」解析器会把该行切成 10 列。
  该 `|` 来自旧数据（v1.1 就有），本轮只是没顺手修掉；Markdown 渲染本身不受影响。

#### 3.1.3 nit R-4 —— `accept_m1.ps1` 的 SUMMARY 与**逐字对等门的真实覆盖范围**

- **SUMMARY 确实打印了，与声称一致**（我自跑两次的日志 `%A2%\accept_run1.log`/`accept_run2.log`）：
  ```
  implemented tools      : 6 / contract 171
  equality gate coverage : 6 tool(s) compared verbatim: project_get_info, … , project_find_files_referencing_symbol
  implemented tools = 6; contract = 171; known_deviation = per-batch verbatim gate only
  ```
- **覆盖范围我已经独立核实过实现**（不是看报告）：
  `accept_m1.ps1:67-74` 的 `$ToolNames` = **6** 个工具（不是上一轮的 2 个）；
  `Compare-ToolListToFixture`（`:136-168`）先按 `$ToolNames` 过滤契约（`:144`），
  再对**每个名字**逐字比较 `name`（`-ceq`）、`inputSchema`（`Get-CanonicalJson`）、`description`（`-ceq`，`:161`），
  并且要求 `($ActualTools.Count -eq $ToolNames.Count)`（`:145`）——即**多一个少一个都不行**。
  → **逐字对等门覆盖的是「已实现的 6 个工具」，不是全部 171**，与 R-4 要求一致。
- **但 SUMMARY 有一处真实缺陷（D-3）**：`accept_m1.ps1:1046-1048` 的
  ```powershell
  Write-Host ("known_deviation        : per-batch gate, NOT a full-contract gate ({0} of {1} contract entries " +
              "are implemented and compared verbatim); …" -f $implementedCount, $contractSize)
  ```
  由于 `+` 与 `-f` 的优先级，`-f` 只作用于**后半段字符串字面量**，前半段的 `{0}`/`{1}` **没有被代入**，
  实测输出就是字面的 `({0} of {1} contract entries are implemented and compared verbatim)`。
  门本身的判定（`gate_scope_declared`，`:1050-1052`）**用 `-f` 正确代入，PASS**，
  所以我把它定为 **minor（文字门可读性）**，不是门失效。

### 3.2 框架

#### 3.2.4 `registration.{h,cpp}` 只有 `register_all_tools()` 且每组一行；组文件各自独立

- `tools/registration.h:40` 只有 `void register_all_tools(MCPToolRegistry &r_registry);` 一个声明。
- `tools/registration.cpp:34` 一个组 include、`:38` 一行组调用；`:36-39` 函数体就是这一行。
- **生产代码里 `register_all_tools` 的唯一调用点**是 `mcp_server.cpp:317`（我 grep 全模块确认；
  其余命中只有测试 `tests/test_mcp_server.cpp:72`）。`_register_tools()`（`mcp_server.cpp:308-318`）
  带 `registry.get_tool_count() > 0` 幂等保护。
- **组文件独立性**：`tools/project_read_template.{h,cpp}` 只 include `../tool_registry.h` 与 `tool_builder.h`，
  不 include 其它组、不改共享文件；`grep -rn "MCPToolDef "` 在非测试代码里**没有任何**直接构造
  （除了 `tool_builder.{h,cpp}` 内部与 `tool_registry.{h,cpp}` 的接口）→ **生产路径只有 `ToolBuilder` 一种注册方式**。
  测试目录里 `tests/test_mcp_server.cpp:112/130/140` 直接构造 `MCPToolDef` 并 `register_tool()`——
  那是测试替身（scope/error probe），不在生产路径上。

#### 3.2.5 `ToolBuilder` **强制**显式声明 —— 我自己构造违规用例

**静态阅读**（`tools/tool_builder.cpp:88-129`）：`build()` 先清空 `r_reason`，然后对
`name/!has_channel/!has_verb/!has_scope/!has_mutating/!has_handler` 逐项收集 `missing`，
非空即 `return false` 且 `r_reason` 形如
`MCPTools::ToolBuilder: tool '<name>' must declare <逗号连接的缺项> explicitly (GDR-16 / GDR-18).`；
通过后还跑一遍 `MCPToolRegistry::validate_tool_name()`（`:122`）。`register_into()`（`:131-144`）
在 `build()` 失败时 `ERR_PRINT(reason)` 并 `return false`，**不进入注册表**。

**我自己构造的违规用例（不是只看代码）**：任务书不允许改仓库文件，但允许「临时改测试并还原」。
我采用更干净的等价做法——**把整棵引擎源码复制到 `%TEMP%\audit002\tree`（robocopy 991 MB，排除 `bin/`、`.git/`），
只在副本里注入探针**，仓库一个字节都没碰：

- 探针（`%A2%\instrument.py` + `%A2%\instrument2.py` 注入到副本的 `tests/test_mcp_server.h`）：
  对 `channel/verb/scope/mutating` 的 **16 种组合**逐一构建：
  - `mask == 15`（四项全给，并挂上 handler）→ 必须 `build()==true`、`reason` 为空、
    `mutating==false`、`scope==BOTH`、`handler!=nullptr`；
  - 其余 **15** 种 → 必须 `build()==false`，且 `reason` 必须包含**每一个缺失维度**的名字
    （`channel`/`verb`/`scope`/`mutating`）**以及 `handler`**；最后断言 `refused == 15`；
  - 再补 3 组：空 `name` → 拒绝且 reason 含 `name`；只缺 `mutating` → `register_into()` 返回 false 且
    `has_tool()==false`、`get_tool_count()==0`；完整声明 → `register_into()` 返回 true 且进表。
- 构建：`scons platform=windows target=editor module_mono_enabled=no accesskit=no d3d12=no tests=yes -j15`
  （记录在 `%A2%\build_tree.log`；用 `accesskit=no d3d12=no` 是因为原始 `bin/build_deps/{accesskit,agility_sdk}`
  已被清理、无法按原签名重建，这**只影响副本**）。
- 运行：`%A2%\tree\bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="[MCPServer]*"`，
  包括 `--test-case="[MCPServer] AUDIT002 every missing declaration combination is refused"`。

**结果**：**15/15 不完整组合被拒绝、缺项名逐项出现在 reason、完整声明通过、
`register_into()` 拒绝入库**——完整原始输出见附录 A 的 **M1**（探针 1 passed / 76 assertions 全绿，
注入副本整模块 54/486 全绿；仓库基线 53/410 也单独复现）。**还原证据**：探针只存在于 `%TEMP%\audit002\tree`；
`git -C F:\RustProjects\godot-mcp-pro\code\godot status --porcelain` 在验收全程只有 4 条
与本任务无关的未跟踪项、**没有任何 M**（附录 A 的 M3）。因此「还原」不仅完成，而且**从未发生修改**。

#### 3.2.6 参数校验三类错误路径（缺参 → `-32602`；`optional_*` 存在但类型错 → `-32602`）

**我用 `curl.exe --data-binary @file` 打 9888 实测**（`%A2%\bodies\*.json`，结果 `%A2%\results_editor.json`）：

| 用例 | 实测响应 |
|---|---|
| `project_search_file_names` 缺 `pattern` | `error.code = -32602`，`message = "Missing required parameter: pattern"` |
| `project_search_file_contents` 缺 `pattern` | `-32602` / `Missing required parameter: pattern` |
| `project_find_files_referencing_symbol` 缺 `pattern` | `-32602` / `Missing required parameter: pattern` |
| `project_search_file_contents` `file_pattern: 5` | `-32602` / `Parameter 'file_pattern' must be a string, got float` |
| `project_search_file_contents` `path: 7` | `-32602` / `Parameter 'path' must be a string, got float` |
| `project_get_settings` `prefix: true` | `-32602` / `Parameter 'prefix' must be a string, got bool` |
| `project_get_settings` `include_default: "yes"` | `-32602` / `Parameter 'include_default' must be a boolean, got String` |

→ **缺参与「存在但类型错」两类都是 `-32602` 且信息可读**，**实现方「比参照实现更严」的声称成立**
（参照实现 `project.rs:152-153/187/241-242/251-252` 用 `and_then(|v| v.as_str()).unwrap_or(default)`
静默吞掉类型错）。这正是 deviation 5，我建议接受（§5）。

#### 3.2.7 编辑器守卫 —— `TOOL_ENABLED` 是否真的不存在 + 游戏进程是否确实不注册 EDITOR 工具

- **`TOOL_ENABLED` 在本 fork 真的不存在**（我自己 grep，不采信报告）：
  - `grep -rn "^\s*#\s*define\s\+TOOL_ENABLED\b"` 整树 → **0 命中**；
  - 把 `TOOL_ENABLED` 当独立 token 搜 `core/ scene/ editor/ modules/`（排除 `TOOLS_ENABLED` 与
    `MCP_EDITOR_TOOLS_ENABLED`）→ 唯一命中是 `tools/tool_builder.h:44` 的**注释**（在解释这件事）；
  - 真正被定义的是 `SConstruct:564` 的 `env.Append(CPPDEFINES=["TOOLS_ENABLED"])`。
  → `tools/tool_builder.h:51-53` 的 `#ifdef TOOLS_ENABLED / #define MCP_EDITOR_TOOLS_ENABLED 1` 是**正确且唯一**的守卫。
- **游戏进程确实不注册 `scope=EDITOR` 工具**（我自己起 9889 实测）：
  - `GET http://127.0.0.1:9889/mcp`（状态路由）→
    `{"is_editor":false,"listening":true,"port":9889,"tools":6,...}`；
  - 9889 的 `tools/list` 与 9888 的 `tools/list` **字节完全相同**
    （两份响应的 sha256 都是 `a726b11a5e00a95b049b114c080479fbcb373f00989a6543c5853053ca90c743`）——
    这不奇怪，因为 B1 模板组 6 个工具全是 `scope=BOTH`；
  - **本轮**没有任何 `scope=EDITOR` 工具被注册（B1 的 editor 组尚未实现），所以「游戏进程里看不到 EDITOR 工具」
    在当前构建上是**平凡成立**的；这条**不能**证明 `register_into()` 的 game-process 分支。
  - **对该分支的独立证据**：源码 `tool_builder.cpp:138-142` 在 `built.scope==EDITOR && !is_editor_process()`
    时**直接 return false**（不进表）；已有测试
    `tests/test_mcp_server.h:738-759`「tool builder keeps editor-only tools out of a game process」
    断言 `registered==false`、`has_tool()==false`、`get_tool_count()==0`（doctest 进程 `is_editor_proces()==false`
    等价于游戏进程）。我**未能**用一个真实 `scope=EDITOR` 工具在 9889 上端到端复现（本轮没有这样注册的工具，
    且不允许改仓库），故此项标为 **`unconfirmed`（端到端）＋ 证据支持（单元/源码级）**，见 §6。

#### 3.2.8 `normalize_project_path` 的安全边界 —— **我自己构造 22 条反例**

我构造了 22 条路径（`%A2%\bodies\trav_*.json`，结果 `%A2%\results_editor.json` 与
`results_game.json`；汇总脚本 `%A2%\b6_trav.py`），对 `project_search_file_names` 与
`project_get_filesystem_tree` **各跑一遍**（9888 与 9889 两端都跑）：

| 路径 | 实测（两个工具一致） | 判读 |
|---|---|---|
| `res://../outside`、`res://./../outside`、`res://src/../../outside`、`res://../`、`res://../../`、`res://a/../b`、`res://src/../src`、`res://..\outside`、`res://sub/../../../outside`、`res://....`、`res://..%2f..%2foutside` | **`-32602` must not walk upwards with '..'** | `..` 全被拒 |
| `res://a//b`、`res://....//outside`、`res://..//` | **`-32602` must not contain an empty segment** | 空段被拒 |
| `res://a/./b`、`res://%2e%2e/`、`res://@/`、`res://sub/../../../outside` | `-32001 not found` | 不存在的目录 → 未找到 |
| `res://. ./outside` | `-32001 not found` | 落空 |
| `res://src/./` | **成功**，返回 `name="." kids=6` | **见 D-4** |
| `res:// /`、`res://.` | **成功**，返回 `name=" "` / `name="."`、`kids=12` | **见 D-4** |

**是否有「读写项目根之外」的绕过？我尽力找了，结论：没找到。**
- 控制组：项目内 `res://inside/secret.txt` 用 pattern `INSIDE_MARKER_AAAA` → 命中 1 条；
  项目外 `%TEMP%\audit002\outside\secret.txt`（内容 `OUTSIDE_MARKER_ZZZZ`）从 `res://` 起搜 → **0 命中**；
  所有 22 条 `..` 变体都被 `-32602` 拦下，没有一条落到项目外。
- 机制层面：`normalize_project_path`（`tool_builder.cpp:270-297`）**先**要求 `begins_with("res://")`，
  **再**拒 `//`（空段）、**再**拒任何位置的 `..`，只有通过后才会 `DirAccess::open()`。
  三个带 `path` 参数的工具（`project_get_filesystem_tree`、`project_search_file_names`、
  `project_search_file_contents`）都**在打开目录/扫描之前**调用了它；第四个能碰磁盘的
  `project_find_files_referencing_symbol` **契约里根本没有 `path` 参数**，扫描恒从硬编码 `"res://"` 起
  （`project_read_template.cpp:626-647`），所以它没有注入面。
- 我**没有**找到 `%2e%2e`、`....//`、混合分隔符、绝对路径（`res://C:/…`）、URL 编码等任何可用于逃逸的形式。

### 3.3 模板组行为

#### 3.3.9 两个迁移工具逐字相等 + 迁移前后无回归（含游戏进程回退路径）

- **逐字相等（我自己从 9888 抓的实况）**：`%A2%\b1_toolslist.py` 把 live `tools/list` 与
  `docs/tools_list.renamed.json` 的 6 条逐字段比较：**`verbatim failures: NONE (6/6 name/description/inputSchema equal)`**，
  且 live 条目的键序（`description,inputSchema,name`）与契约一致。
- **迁移回归护栏真的存在**：M1 快照（`git show 42657f863f:modules/mcp_server/tests/test_mcp_server.h`）
  里 `tools/list exposes exactly the two ported tools` 的字节串是
  `…"tools":[{"description":"获取项目信息","inputSchema":{…},"name":"get_project_info"},{"description":"获取项目设置",…,"name":"project_get_settings"}]}}`；
  现在的 `tests/test_mcp_server.h:639-660` 断言的前两条**逐字就是 M1 的那两条**（仅 `name` 由旧名改成新名，
  而旧名 `get_project_info/get_project_settings` 与新名**同名**）→ 迁移**前两条位置与字节未变**。
- **游戏进程回退路径**：`_get_screen_size()`（`project_read_template.cpp:175-196`）在
  `MCP_EDITOR_TOOLS_ENABLED` 且 `is_editor_hint()` 时用 `EditorInterface` 的 base control，
  否则回退到 `SceneTree` 根视口，最后 `Vector2()`。我在 9889（`is_editor:false`）实打
  `project_get_info` → `{"editor_screen_size":{"height":64.0,"width":64.0},"project_name":"AUDIT002 Scratch","version":""}`
  （**无 crash、字段齐全**）。注意这个 64×64 的**回退实现早于本任务存在**：
  `git show 42657f863f:modules/mcp_server/tools/project.cpp:168-185` 已经是同一段
  `#ifdef TOOLS_ENABLED … 否则 SceneTree 根视口` → **本任务没有引入行为回归**，只是把宏换成了模块别名。
  （参照实现 `project.rs:80-97` 在拿不到 base control 时给 `{width:0,height:0}`，
  本模块在游戏进程给视口尺寸——这是**既有的、早于 TASK-002 的**增强，见 deviation 裁决 §5。）

#### 3.3.10 两个取消合并的工具**必须是两个不同实现** —— 三项差异我全部独立复现

我用**同一个自造工程**（`%A2%\proj`：`src/case_target.gd` 同时含 `FooBar`/`foobar`/`FOOBAR`；
`src/cap_source.gd` 含 60 行 `cap_probe_NNN`；`many/` 下 130 个含 `bulk_marker_xyz` 的文件）

| 检查项 | `project_search_file_contents` 实测 | `project_find_files_referencing_symbol` 实测 | 差异真实？ |
|---|---|---|---|
| **输出形状** | `{"count":50,"matches":[{"file":…,"line":2,"text":"var cap_probe_000 = 0"},…]}` 逐行 | `{"pattern":"cap_probe","matches":[{"file":"res://src/cap_source.gd","lines":[2,3,4,5,6]}],"count":1}` 按文件聚合 | **是** |
| **大小写** | pattern `foobar` → **3 命中**（`FooBar`/`foobar`/`FOOBAR`） | pattern `foobar` → **1 命中**（只有第 3 行） | **是** |
| **上限** | 60 行命中 → `count=50`（截断） | 130 个文件命中 → `count=100`（截断） | **是（50 vs 100）** |
| **每文件行数上限** | 无此项 | 60 行命中同一文件 → `lines` 只 5 个元素 | **是（≤5）** |
| 跳过目录 | `addons_dir_token` → 0 命中（跳过 `addons`） | 同 → 0 命中 | 一致（都跳过） |
| 隐藏项 | （未跳过 `.godot` 之外的隐藏？契约只说跳过 addons/.godot） | `hidden_token` → 0 命中（隐藏目录/文件被跳） | **是**（finder 额外跳隐藏） |
| 后缀白名单 | `.xyz` → 0；`.md` → 命中 | `.tres` → 命中；只扫 4 种后缀 | **是** |
| CRLF 行号 | `crlf.gd` → `line 2,3` | `crlf.gd` → `lines [2,3]` | 一致（都合 Rust `lines()`） |

→ **两个工具确实是两套独立实现、行为可区分**，GDR-17 的「不得合并回同一实现」在本组被真实满足。

**关于「同一输入 3 命中 vs 0 命中」——我独立复现的结果是「3 vs 1」，不是「3 vs 0」（D-2）**：
实现方报告（§某处）说同一输入得到 3 vs 0；我用 pattern `foobar` 得到
`contents=3`（两行 `foobar` 形态 + 一行 `FOOBAR`）而 `find=1`（只有那一行真正含小写 `foobar`）。
`3 vs 0` 只有在**查询串本身在文件中一个大小写形态都不存在**时才出现（那种情况下另一个工具自然也是 0），
所以那句话作为「同输入差异」的例子不成立。**机制本身（不敏感 vs 敏感）没错**，
错的是那句自述的数字。这是我判的 **minor（自述不准确）**。

#### 3.3.11 `project_search_file_names` 只按文件名匹配 + 上限 200 真实生效

- **只按文件名**：工程里 `contentonly/plain_holder.gd` 的**内容**含 `content_only_token_qwerty`
  但**文件名不含**；用 `project_search_file_names(pattern="content_only_token_qwerty")` → **`count=0, matches=[]`**。
- **上限 200**：`names/` 下 250 个 `nameprobe_NNN.gd`（Godot 为每个 `.gd` 又生成了 `.gd.uid`，共 ~500 个候选）
  → `project_search_file_names(pattern="nameprobe")` 返回 **`count=200`**（截断）；
  `pattern=".gd" path="res://names"` 同样 **`count=200`**；两次重复跑结果一致（顺序确定）。
- 大小写不敏感：`pattern="NAMEPROBE"` → 同样 200 条、命中同样文件。
- **不跳过 `addons`/`.godot`/隐藏**（与参照 `project.rs:159-191` 一致，也是它与内容搜索的差异之一）：
  `pattern="skipped_in_addons"` → 命中 `res://addons/skipped_in_addons.gd`；`pattern="hiddenfile"` → 命中
  `res://.hiddenfile.gd`；`pattern="skipped_in_dotgodot"` → 命中 `res://.godot/skipped_in_dotgodot.gd`。

#### 3.3.12 三类证据真实可复现（我抽 3 个工具各验一遍，用 `curl.exe --data-binary @file`）

全部经 `curl.exe -sS -X POST http://127.0.0.1:9888/mcp -H 'Content-Type: application/json'
--data-binary @<file>`（JSON body 一律走文件，避免命令行丢引号）：

| 工具 | 成功 | 缺参 | 底层失败 |
|---|---|---|---|
| `project_search_file_names` | `{"count":200,"matches":[…]}` | 缺 `pattern` → `-32602 Missing required parameter: pattern` | `path="res://__nope__"` → `-32001 Directory 'res://__nope__' not found`＋`data.suggestion="Call the tool without 'path' (or with 'res://') to address the project root"` |
| `project_search_file_contents` | `{"count":50,"matches":[{file,line,text}…],"query":"cap_probe"}` | 缺 `pattern` → `-32602` | `path="res://__nope__"` → `-32001 Directory … not found` |
| `project_get_filesystem_tree` | `{"tree":{…}}`（`max_depth:0` 也可复现） | —（无必填参数；改验 `path` 类型错 → `-32602`） | `path="res://__nope__"` → `-32001` |

另外 `project_get_info`（端到端 9888 与 9889 都成功）、`project_get_settings`（`prefix` 过滤成功 + 类型错 `-32602`）
也各验了一遍。**三类证据真实可复现**；成功的 payload 形状与契约描述一致。

### 3.4 组清单与工程门

#### 3.4.13 `docs/tool-groups.json` —— **我自己重算**（不用 `docs/scripts/check_tool_groups.py`）

我写了两份互不依赖的脚本：`%A2%\c1_groups.py`（清单/契约/分组不变式）与
`%A2%\c2_b1.py`（从 `DESIGN-DETAIL.md` §10 抽 B1 旧名单 → 过映射 → 与清单比对）。

1. **41 个工具恰好各出现一次**：`total tools listed: 41`，`distinct: 41`，`duplicates: {}`，
   `in expected, not grouped: []`，`in grouped, not expected: []` → **双向差集为空**。
2. **与 §10 B1 清单等价**：我从 `DESIGN-DETAIL.md:201-209` 的 B1 段落抽出 **42 个旧工具 token
   （distinct 42，无重复，全部存在于映射）**，经映射换算得 42 个新名，
   其中 `disposition=merge_into` 的恰好 1 个（`get_editor_performance → editor_get_performance_monitors`），
   去掉后 **= 41**，与清单**集合完全相等**。即 `tool-groups.json` ≡ **42 旧 − `get_editor_performance`**。
   （同时确认 `get_editor_performance`/`get_performance_monitors` **不在** 171 条契约里，
   而 `editor_get_performance_monitors` 在——契约的 merge 去重是自洽的。）
3. **每组一个 channel + 一个 mutating 值**：对每组把成员映射回 `tool-rename-map.json`
   取 `channel`/`mutating`，与组声明比对 → `problems: NONE`。
   实测分组：`project_read_template`(6,project,False)、`project_read_analysis`(7,project,False)、
   `project_read_files`(6,project,False)、`project_write_resource_scene`(4,project,**True**)、
   `editor_read_scene_inspector`(7,editor,False)、`editor_write_scene_editor`(10,editor,**True**)、
   `running_game_read_scene`(1,running_game,False)。
4. **组 ≤10**：最大 10（`editor_write_scene_editor`）→ 满足。
5. **名字都存在于契约**：`grouped names missing from the contract: []`（契约 171 条）。
6. 额外做了 GDR-16 一致性重算（`%A2%\c4_lint.py`）：41 个工具的 `new_name` 都能按
   `<channel>_<verb>_<object>` 与映射声明逐段对齐 → `inconsistencies: NONE`。
7. 作为**交叉参考**（不作证据）：仓库自带 `docs/scripts/check_tool_groups.py` 输出
   `TOOL-GROUPS CHECK PASS`（41 恰好各一次 / 名字在 171 契约 / 每组一 channel 一 mutating / 41==42−1），
   与我的重算结论一致；它同时打印出该文件的 `5443` B / `9644911a…0e59`，与 E1 一致。

#### 3.4.14 工程门自己跑

| 门 | 命令 | 实测结果 | 实现方声称 | 判定 |
|---|---|---|---|---|
| doctest（模块） | `--headless --test --test-case="[MCPServer]*"` | **test cases 53 / 53 passed / 0 failed**；**assertions 410 / 410 passed** | 53/53（410 断言） | **一致** |
| 全引擎 | `--headless --test` | **1479 passed / 0 failed / 3 skipped**（assertions 424691/424691） | 1479/0/3 | **一致** |
| `accept_m1.ps1` ×2 | `powershell -File …accept_m1.ps1` | 两次都 **21/21 cases passed**，退出码 **0**；`gate_scope_declared` PASS（`implemented=6 contract=171 expected_contract=171`）；`guard_user_port_9877` PASS（`pid_before=36392 pid_after=36392`） | 21/21 连跑两次 | **一致** |
| 契约子集门 | `check_contract_subset.ps1 -Group project_read_template` | **3/3 checks passed**：`editor_9888_contract_subset` PASS、`game_9889_contract_subset` PASS、`guard_user_port_9877` PASS（`pid 36392→36392`）；两个端点各 **tools=6** 且 6 条 `name/description/inputSchema` 全 `True` | 9888 与 9889 逐字 6/6 | **一致** |

补充实测：doctest 运行时会打印若干**故意的** `ERROR:`（命名 lint 反例、`[MCP] SceneTree never became available`），
那是负例测试的输出，不影响 `53/53`、`410/410` 的结论。

#### 3.4.15 反例工作：分组对**并行**移植是否真的安全

**组间无共享文件 —— 生产代码层面成立**：7 个组各自拥有 `tools/<group>.{h,cpp}`；
`tools/registration.{h,cpp}`、`tools/tool_builder.{h,cpp}`、`tool_registry.{h,cpp}` 是共享**只读**（本轮之后不再改）。

**但「每组只改自己的文件 + 一行注册」这句话有一个真实冲突点，我做了实证**：
`tools/registration.cpp` 是所有组都要改的**同一个文件的同一处**（`:32-38`：
一个 include 区 + 一个调用区）。我用 `git merge-file` 在 `%A2%\merge` 里模拟
「agent A 加 `project_read_analysis` 的 include+call」「agent B 加 `project_read_files` 的 include+call」：

```
merge-file exit=2
conflict markers: 4
<<<<<<< agentA.cpp
    register_project_read_analysis_tools(r_registry);
=======
    register_project_read_files_tools(r_registry);
>>>>>>> agentB.cpp
```

→ **两个并行子代理各自在 `registration.cpp` 同一处各加一行，三方合并必然产生 2 处冲突**
（include 区 1 处 + 调用区 1 处）。所以：

- **组文件本身是安全的**（互不重叠），**共享注册点是唯一的串行瓶颈**；
- 在「多子代理共享同一工作树」的现实下，如果它们**真的并发写同一个 `registration.cpp`**，
  不是「合并时冲突」而是**直接互相覆盖**（后者更危险：丢掉一个组却仍是绿的，因为该组的
  `check_contract_subset.ps1 -Group xxx` 不会跑）；
- **建议（不阻塞本批）**：后续并行批次要么①**串行化**「加注册行」这一步（每个子代理完成后由父代理统一追加），
  要么②把注册改成**每组建一个自注册文件**（例如 `tools/<group>.register.cpp` 里定义
  `register_<group>_tools`，`registration.cpp` 用**构建期生成的 include 列表**），
  让每个子代理只新增文件、永不编辑共享文件。①的成本低于②，且对 7 组规模已经够用。
  另外建议把「所有组必须经 `ToolBuilder` 注册」写进下一批任务书（`MCPToolRegistry::register_tool`
  仍是 public，存在绕过 `mutating`/editor 守卫的路径；本轮没有绕过，但约束没有机制保证）。

### 3.5 实现方 9 条 deviations —— 逐条裁决建议

| # | 实现方声称 | 我的独立裁定 | 建议 |
|---|---|---|---|
| 1 | 组数 7 而非任务书建议的 4–6 | **成立且算术下界就是 7**：我按映射重算 project 23（read 19 + write 4）、editor 17（read 7 + write 10）、running_game 1；在「每 channel + 每 mutating 一组、组 ≤10」下，project 至少 3+1、editor 至少 2、game 1 = 7。清单实测与之一致（§3.4.13） | **接受**（并建议把「组数由不变式导出，不是自由选」写进规范） |
| 2 | 两个迁移工具的三类证据只有部分可达 | **成立**：`project_get_info` 无参数且全函数（我实测传任意参数都成功）；`project_get_settings` 无外部资源（底层失败不可构造）。用「可选参数类型错 → `-32602`」替代缺参类是**合理**的替代证据 | **接受** |
| 3 | `find_files_referencing_symbol` 底层失败类不可达 | **成立**：契约无 `path`，`open_project_dir("res://")` 在活工程不可失败（源码 `project_read_template.cpp:634-637` 的守卫真实存在）。我实测 9888/9889 上该工具恒从根起扫成功 | **接受** |
| 4 | `path` 不存在返回 `-32001`（参照是静默空） | **成立且更好**：参照 `project.rs` 对不存在的 `path` 静默返回空；本模块按 GDR-14 给 `-32001 + data.suggestion`。我实测 `res://__nope__` → `-32001` 带 suggestion；且 `-32001` 与 `-32602`/`-32000` 的边界在 `tool_registry.h:49-62` 有明确注释 | **接受**（强烈建议保留；这是可操作性提升，不是偏差） |
| 5 | `optional_*` 对「存在但类型错」报 `-32602` | **成立**：实测 4 例（§3.2.6）。参照是 `unwrap_or(default)` 静默吞掉。任务书 §2.2.2 明确要求「失败 → `-32602` 且信息可读」 | **接受** |
| 6 | `#ifdef TOOL_ENABLED` → 等价守卫 `MCP_EDITOR_TOOLS_ENABLED` | **成立**：我独立确认 `TOOL_ENABLED` 整树 0 定义，`TOOLS_ENABLED` 由 `SConstruct:564` 定义（§3.2.7）。任务书原文「（或等价守卫）」已授权此替换 | **接受** |
| 7 | 编辑了 `DESIGN-DETAIL.md`（新增 GDR-19/§17 + 同步 §1/§7） | **成立且必要**：§17 的三节（17.1 注册分组 / 17.2 助手 / 17.3 双目标守卫）与已交付代码**逐条对得上**（我核了 §17.2 的四条助手语义、§17.3 的两条守卫）。后续 6 组会照它实施，脱节会把错误设计扩散 | **接受**（建议把「规范与交付同步」写成下一批的显式义务） |
| 8 | 「工作树残留 `M …/TASK-002-b1-framework.md`，在我开始前就存在」 | **已过时**：我实测 `git status --porcelain` 无任何 `M`（只有 4 条无关未跟踪项），且 `74d565f24d` 提交信息正是「finalize the TASK-002 brief and add the TASK-AUDIT-002 brief」→ 该文件**已被提交**。报告写这段时的状态与验收时的状态不同 | **要求改写**（低优先）：报告 §9-8 应更新为「该文件随后已由 `74d565f24d` 提交」 |
| 9 | `git diff --name-only 1090d04803..HEAD | grep -v '^modules/mcp_server/'` = 0 命中 | **成立**：我实测 **0** 命中；`1090d04803..HEAD` 共 26 个文件，**全部**在 `modules/mcp_server/` 下 → 符合 GDR-1「除 `modules/mcp_server/**` 外不得改引擎源码」 | **接受** |

---

## 4. 缺陷（defects）与反向发现

### D-1（minor，需决策者裁决）—— `tools/list` 的**顺序**与 v1.2 契约不同

- **claim**：实况 `tools/list` 的第 2 条是 `project_get_settings`，而 `docs/tools_list.renamed.json`
  里它的位置是第 5 条（在 4 个 search/tree 工具之后）。
- **evidence**（我自己的实况抓取 + 脚本比对，`%A2%\b1_toolslist.py`）：
  ```
  live order : ['project_get_info','project_get_settings','project_get_filesystem_tree',
                'project_search_file_names','project_search_file_contents',
                'project_find_files_referencing_symbol']
  contract   : ['project_get_info','project_get_filesystem_tree','project_search_file_names',
                'project_search_file_contents','project_get_settings',
                'project_find_files_referencing_symbol']
  verbatim failures: NONE (6/6 name/description/inputSchema equal)
  ```
- **location**：`tools/project_read_template.cpp:653-682`（把 `project_get_info` 与
  `project_get_settings` 一起注册在最前）；契约顺序见 `docs/tools_list.renamed.json`（= 旧 fixture 的过滤顺序）。
- **为什么所有门都没抓住它**：`DESIGN-DETAIL.md:316` 的对等门定义是「`tools/list` 与期望契约
  **逐字相等**（name / description / inputSchema）」——**枚举的是字段，不是顺序**；
  `accept_m1.ps1:144-166` 与 `check_contract_subset.ps1` 都是**按名字集合**比对；
  `tests/test_mcp_server.h:639-660` 断言的是**模块自己的**顺序（它同时是 M1 迁移护栏）。
- **我的判读**：这不是行为错误，但它是**当前唯一无法由门发现的一致性缺口**；对顺序敏感的消费者
  （例如按位置做 diff/golden 的 harness）会看到与契约不同的序列。**不能**由我擅自决定哪边是对的：
  「先差分说明（v1.2 契约是旧 fixture 的顺序）」与「迁移护栏优先（M1 顺序）」两个诉求都能自洽。
  由于 M1 顺序是既有事实、且 gates 明确按集合设计，我倾向**把契约定为「集合语义」并在契约 `_meta`
  里写明"order is not part of the contract"**；但如果决策者要求逐条对齐契约顺序，则改
  `project_read_template.cpp` 的注册次序即可（一行级改动，但会同时要求重写测试里的字节串）。
- **recommendation**：请决策者裁决并**把裁决写进契约/规范**（二选一），下一批任务书据此执行。

### D-2（minor）—— 实现方报告的「3 vs 0」自述实例不成立（机制正确，叙述错误）

- **claim**（报告 §5.5/§5.6，`:319-344`）：同一工程、pattern 取 `playerhealth` 时
  `project_search_file_contents` = `count:3`，而 `project_find_files_referencing_symbol` = `count:0`，
  用作「两个工具确实是两套实现」的直接检验点。
- **evidence / 我的分析**：
  1. 报告自己给的 `count:3` 命中列表（`:321-323`）里，**包含了一行实际只含小写 `playerhealth` 的文本**
     （`res://PLAYER_README.md` 第 2 行 `the player reads playerhealth`）。
     该工具若要同时命中第 3/5 行的 `PlayerHealth` 与第 2 行的小写形态，
     **必须把命中比较与 `text` 输出都做小写化**；而报告对**同一** pattern（全小写 `playerhealth`）
     的查找工具却给出 0，两者对「同一文件里就存在小写 `playerhealth`」给出相反结论 → **这份自述内部不自洽**。
  2. 我按源码复核：`project_read_template.cpp:505-509` 用 `lines[i].to_lower().contains(p_query.to_lower())`，
     但输出 `hit["text"] = lines[i].strip_edges()`（**保留原文大小写**）。
     即源码**不会**把输出小写化 → 报告那条 `"text":"the player reads playerhealth"` 作为「pattern 小写时的原文」是巧合，
     不足以支撑「3 vs 0」。
  3. 我用**机制本身**在自造工程上独立复现（`%A2%\proj`，`src/case_target.gd` 三行分别是
     `FooBar` / `foobar` / `FOOBAR`）：pattern `foobar` →
     `search_file_contents` = **3**（不敏感，含 `FooBar`、`FOOBAR`）；`find_files_referencing_symbol` = **1**
     （只那份文件、只 `lines:[3]`，即只有真正含小写 `foobar` 的行）。pattern 保持大小写一致时两者都能各自命中。
- **正确的表述**：这两个工具在**同一输入**上的真实差异是 **3 vs 1**，
  而且「差 3 条」的成因是**大小写不敏感 vs 敏感**；**「上限 50 vs 100」「逐行 vs 按文件聚合」**在
  `bulk_marker_xyz`（130 文件 ≥100、50 命中）与 `cap_probe`（聚合 `lines:[2,3,4,5,6]`）两个用例上**已由我实测确证**。
- **location**：`docs/reports/REPORT-002-b1-framework.md:319-344`；**实现本身无误**
  （`project_read_template.cpp:495-521` vs `575-624`）。
- **recommendation**：把该自述实例改成可复现的形态：pattern 取 **`FOOBAR`** 时
  `search_file_contents` = **3**、`find_files_referencing_symbol` = **1**（我实测，见下「实测补充」），
  即**同一输入下数差来自大小写规则**；若要强调「0」，应给出「文件里没有该 pattern 的精确大小写形态」的工程
  （那样查找方为 0，而搜索方因不敏感可能仍 >0）。**不改代码**。

  > 实测补充（我自己的 `%A2%\proj`，9888）：
  > `pattern="FOOBAR"` → contents `{"count":3,"matches":[{line:2,text:"var FooBar = 1"},{line:3,…},{line:4,…}],"query":"FOOBAR"}`；
  > find `{"count":1,"matches":[{"file":"res://src/case_target.gd","lines":[4]}],"pattern":"FOOBAR"}`。

### D-3（minor）—— `accept_m1.ps1` SUMMARY 的 `known_deviation` 行没有代入数值

- **claim**：SUMMARY 声称会打印「{0} of {1} contract entries」的填充值，实测打的是字面量。
- **evidence**（我的两次自跑日志 `%A2%\accept_run1.log` / `accept_run2.log`，UTF-16 记录）：
  ```
  known_deviation        : per-batch gate, NOT a full-contract gate ({0} of {1} contract entries are implemented and compared verbatim); …
  ```
- **location**：`modules/mcp_server/scripts/accept_m1.ps1:1046-1048`（`"…" + "…" -f $a,$b` 的运算符优先级）。
- **impact**：`gate_scope_declared`（`:1050-1052`）**本身正确代入并通过**，门没失效；只是给人看的那一行
  出现 `{0}/{1}`。对「防止把批次门误读为全量门」的目标有轻微削弱。
- **recommendation**：把拼接与 `-f` 用括号分开：

  ```powershell
  Write-Host (("known_deviation : per-batch gate, NOT a full-contract gate ({0} of {1} contract entries " +
               "are implemented and compared verbatim); unimplemented tools are deliberately absent from " +
               "tools/list (GDR-7)") -f $implementedCount, $contractSize)
  ```

### D-4（nit）—— `normalize_project_path` 不做 `.` 段归一，`res://.` / `res:// ` / `res://src/.` 被当作合法路径

- **claim**：`res://.`、`res:// `（一个空格）、`res://src/.` 都能通过归一化并成功打开一个目录。
- **evidence**（`%A2%\b6_trav.py` + `results_editor.json`）：
  `project_get_filesystem_tree(path="res://.")` → 成功、`tree.name="."`、`kids=12`；
  `path="res:// "` → 成功、`tree.name=" "`、`kids=12`；
  `path="res://src/./"` → 成功、`tree.name="."`（返回的 `path` 字段是 `res://src/.`，与实际 `src` 不符）。
- **impact**：**无安全影响**（`DirAccess` 把 `.` 解析为当前目录，仍在项目根内；控制组 `trav_control_outside` 证明项目外文件搜不到）。
  影响的是**返回值的可读性/规范性**：`res://src/.` 会被原样回显，而不是折叠成 `res://src`。
- **recommendation（低优先，下一批顺手做）**：在 `normalize_project_path` 里折叠 `.` 段、并 `strip_edges()` 后
  再校验（现在只 `strip_edges()` 了输入首尾，但 `res:// ` 的空格在 `res://` 之后被保留）。

### D-5（nit）—— `TOOL-NAMING.md` 有一行的 `reason` 单元格含未转义 `|`

- **claim**：`get_project_info` 那一行的 `reason` 含一个裸 `|`，使该行按 `|` 切分得 10 列。
- **evidence**：`%A2%\a4_naming.py` → `map reasons containing a raw '|': 1  ('get_project_info', 1)`
  与 `PIPE_ANOMALIES: [('`get_project_info`', 1)]`；其余 173 行均正常。
- **location**：`docs/TOOL-NAMING.md` 第 2 节 `get_project_info` 行（源自映射 `reason` 的既有文本）。
- **impact**：Markdown 渲染正常；只有「按 `|` 切 9 列」的机器消费者会踩到。
- **recommendation**：让 `docs/scripts/gen_table.py` 在渲染前把 `reason` 里的 `|` 转义成 `\|`，然后重跑生成器
  （N-1 的同一条路径）。

---

## 5. 我在验收中未能证实的（unverifiable / unconfirmed）

1. **真实游戏进程下 `scope=EDITOR` 工具的端到端不可见性**：本轮 B1 没有任何 `scope=EDITOR` 工具被注册，
   所以 9889 的 `tools/list` 过滤**平凡成立**，无法构成对该分支的端到端证据。
   证据级替代：源码 `tool_builder.cpp:138-142` + 单测 `test_mcp_server.h:738-759`（我读了断言，doctest 53/53 含它）。
   → **标 `unconfirmed`（端到端）**。
2. **`accept_m1` 的非核心 case 行为**：我只跑了整个脚本（21/21）并读了日志，未逐 case 独立复现全部 21 个；
   与本任务相关的 `case3_tools_list_fixture`、`case5_tools_call_invalid_params`、`case12/13/14`（游戏/端口纪律）
   在两次运行里都 PASS，但我**没有**逐条重造它们的输入。
3. **`git merge-file` 模拟的是「三方合并」，不是「并发写同一文件」**：真实并发写会互相覆盖，
   我的实证给的是**下界**（至少会冲突）。这属推断，但方向确定。
4. **build 原始选项**：原始 `bin/build_deps/{accesskit,agility_sdk}` 已不存在，
   我无法按原签名做**增量**重建；我的 ToolBuilder 实测是在**独立副本**里用
   `accesskit=no d3d12=no tests=yes` 重建的（这不影响 ToolBuilder 源码本身的行为）。
5. **第 3.2.5 项的探针是我自己的**：它验证的是被验收 `tool_builder.{h,cpp}` 的**真实行为**，
   但探针写在副本里、不是仓库测试的一部分；因此它证明的是「实现会拒绝」，
   而**不是**「仓库里长期存在这样的回归护栏」（后者由仓库基线测试
   `[MCPServer] tool builder refuses an incomplete declaration` 覆盖，我单独复现为 1 passed / 17 assertions
   全绿，见附录 A-M1 末段）。

---

## 6. 结论与下一步建议

### 结论

- **机械层 / 行为层 / 框架层 / 工程门：全部 pass**（15 项逐条见 §3；5 个门我全部自跑，数值与声称一致：
  doctest 53/53·410、全引擎 1479/0/3、accept 21/21 ×2、契约子集 9888+9889 3/3；
  框架层的 ToolBuilder 拒绝行为**已用我自造违规用例实测**：15/15 缺项组合被拒 + 完整声明通过，
  见附录 A-M1）。
- **7 条判别点全部对回迁移源码为真**，四对二选一的裁决：**全部「够」**。
- **两个取消合并工具的三项差异（形状 / 大小写 / 上限 50 vs 100）我全部独立复现为真**，
  两套实现确实独立。
- **路径安全**：22 条自造反例 + 项目内外控制组，**没有找到任何逃逸项目根的方式**。
- **缺陷**：D-1（`tools/list` 顺序，需裁决）、D-2（报告自述实例 3 vs 0 不成立，机制本身正确）、
  D-3（SUMMARY 未代入 `{0}/{1}`）、D-4/D-5（两个 nit）。**没有一个是行为/安全错误**。
- **并行安全**：组文件互不重叠成立；但 `tools/registration.cpp` 是**所有组共写的同一处**，
  我已用 `git merge-file` 实证必然冲突（exit=2、2 处 conflict）——这是下一批并行前必须处理的**流程风险**。

### next_step_recommendation

1. **请决策者对 D-1 裁决**（`tools/list` 顺序是否属于契约）：二选一后再派下一批。
2. D-2/D-3/D-5 可合并成一次「文字+脚本+生成器」的小修（不碰行为代码），修完重跑 accept 与 gen_table。
3. 下一批任务书里**明文规定**：所有组必须经 `ToolBuilder` 注册；`registration.cpp` 的注册行由**父代理统一追加**
   （或改成每组合自注册文件），避免并发覆盖。
4. D-4 作为低优先项挂在下一批顺手做。
5. 建议把「顺序语义」与「组数由不变式导出」写进 `DESIGN-DETAIL.md`，让后续批次不再重复这两处歧义。

---

## 附录 A：实测输出区块（本报告所有的关键原始输出）

### M1 — 注入副本里的 ToolBuilder 违规探针（§3.2.5）—— **实测通过**

构建（副本内，仓库零改动）：`scons platform=windows target=editor module_mono_enabled=no
accesskit=no d3d12=no tests=yes -j15`，`%A2%\build_tree.log` 尾部 = `EXIT_CODE=0`、
`Time elapsed: 00:12:24.14`；二进制 = `%A2%\tree\bin\godot.windows.editor.x86_64.console.exe`。

**探针 A（16 种声明组合）** `%A2%\violation_run.log`：
```
$ ./bin/godot.windows.editor.x86_64.console.exe --headless --test --test-case="[MCPServer] AUDIT002*"
[doctest] test cases:  1 |  1 passed | 0 failed | 1482 skipped
[doctest] assertions: 76 | 76 passed | 0 failed |
[doctest] Status: SUCCESS!
```
探针内容（`%A2%\instrument2.py`）：对 `channel/verb/scope/mutating` 的 16 种组合，
`mask==15`（四项齐全）必须 `build()==true`、`reason` 为空、`mutating==false`、`scope==BOTH`、`handler!=nullptr`；
**其余 15 种全部**必须 `build()==false`、`reason` 必须包含**每一个**被省略维度的名字（`channel`/`verb`/`scope`/`mutating`），
且必须包含 `handler`；最后断言 `refused == 15`。
再补 3 组：**空 name** → 拒绝且 `reason` 含 `name`；**只缺 `mutating`** → `register_into()` 返回 false、
`has_tool()` false、`get_tool_count()==0`；**完整声明** → `register_into()` 返回 true 且进表（证明上面的拒绝不是名字本身不可注册）。

调试中间证据（`AUDIT002DBG` 一次临时插桩，已移除）：16 次迭代 `mask=0..14 → ok=false`、
`mask=15 → ok=true`，与断言一致。探针 C（整模块回归）`%A2%\module_tests_instrumented.log`：
```
[doctest] test cases:  54 |  54 passed | 0 failed | 1429 skipped
[doctest] assertions: 486 | 486 passed | 0 failed |
```
（= 仓库基线 53/410 + 本探针 1 test case / 76 assertions；**注入副本全绿**。）

`register_into()` 拒绝时打印的真实消息（探针 C 日志里可直接看到）：
```
ERROR: MCPTools::ToolBuilder: tool 'project_get_no_mutating_probe' must declare mutating explicitly (GDR-16 / GDR-18).
   at: MCPTools::ToolBuilder::register_into (modules\mcp_server\tools\tool_builder.cpp:135)
```

**结论：`ToolBuilder` 真的会拒绝缺失声明——不是只看代码。** 且**仓库基线自带的**
`[MCPServer] tool builder refuses an incomplete declaration` 我也单独跑过并复现（`%A2%\existing_case_run.log`）：
`test cases: 1 | 1 passed`、`assertions: 17 | 17 passed`（其中含 `bare`【仅 name+description，无 schema 无 handler】被拒
且 `reason` 逐项含 `channel/verb/scope/mutating`、`partial`（只给 `mutating`）被拒且 `reason` 含 `channel` 而不含 `mutating`）。

### M2 — 状态路由与工具数（§3.2.7）

```
GET http://127.0.0.1:9888/mcp
{"connections":1,"frame_count":4487,"is_editor":true,"listening":true,"port":9888,"server":"godot-mcp-rs","status":"ok","tools":6,"transport":"streamable-http"}

GET http://127.0.0.1:9889/mcp
{"connections":1,"frame_count":5523,"is_editor":false,"listening":true,"port":9889,"server":"godot-mcp-rs","status":"ok","tools":6,"transport":"streamable-http"}
```

### M3 — 工作树还原证据（§3.2.5 的要求）

```
$ git -C F:\RustProjects\godot-mcp-pro\code\godot status --porcelain
?? .graphifyignore
?? build-m0.cmd
?? graphify-out/
?? install-deps-m0.cmd
```

**没有任何 `M`/`A`/`D`**：探针从未落到被验收仓库（它只存在于 `%TEMP%\audit002\tree`），
所以「临时改测试再还原」这一步在本轮是「**不需要还原，因为从未修改**」。
