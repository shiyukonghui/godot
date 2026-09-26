# MCP-SERVER-HANDOVER — `modules/mcp_server` 收口/移交文档

> 本文件是 **TASK-073 B** 的交付物。它把「已经建成的模块长什么样、门怎么跑、边界在哪里、
> 还差什么」一次讲完，供**下一个没有本项目上下文的人**接手。
>
> **阅读契约**：本文**每一条结论都带锚点**，锚点写法见 §0.1；读者按 §4 的复现步骤可以自己
> 重算机器数字，或按锚点里的证据路径核对。**本文不引入任何未经锚定的新主张**（§6 自检）。

---

## 0. 元信息与锚点

| 项 | 值 |
|---|---|
| 仓库 / 分支 | `F:\RustProjects\godot-mcp-pro\code\godot`，`feature/mcp-server-module` |
| 本文写作时的 HEAD | **`b6fbb917b`**（`git rev-parse --short=9 HEAD`） |
| 契约（唯一权威） | `modules/mcp_server/docs/tools_list.renamed.json`，**176 条**，155 872 B，sha256 **`701539829ed8fcaa227f280fb6bff71b96522248cd9c4b84f2073c27eb17cfe0`** |
| 命名事实源 | `modules/mcp_server/docs/tool-rename-map.json`，sha256 `2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd`（70 917 B） |
| 组清单 | `docs/tool-groups.json`（B1/B2 与 B3/B4/B5 各自的姊妹文件）与 `docs/tool-groups-added.json`（5 个新增工具） |
| **9877** | 用户正在用的 Godot 4.7.1-mono 编辑器端口（历史 PID 36392）——**绝不占用、绝不杀、绝不重启**；本模块的门只用 **9888（编辑器）/ 9889（游戏）** |
| 未 push | 全程只做本地提交 |

### 0.1 锚点写法（本文统一使用）

- `[sha:<前 9 位>]` —— 该结论**测自那个提交**（D86 纪律：结论必须绑提交，不能只说「现在」）。
- `[契约:<前 12 位>]` —— 该结论的对象是契约文件的某个 sha256 前缀。
- `[文件:行]` —— 引擎/模块源码的**实测行号**（行号在 `b6fbb917b` 上核过）。
- `EV73/EV72/EV71/EV61/EV68` = `modules/mcp_server/docs/reports/evidence/` 下的 `task073/task072/task071/task061/task068` 子目录。
- `[报告:<文件> §x]` —— 该结论的完整推导在报告里。

### 0.2 关键提交锚点

| sha | 内容 | 用途 |
|---|---|---|
| `57277407e7` | fork master 基线（`git merge-base HEAD origin/master`） | 引擎补丁净改动的**基线侧** `[报告:REPORT-AUDIT-ENGINE.md §1.1]` |
| `5f3e7fb441` | **引擎补丁 1**（C# 真结论） | `[报告:REPORT-055-csharp-compile-verdict-patch.md]` |
| `96f631addb` | **引擎补丁 2**（`ProjectSettings` 按节发布） | `[报告:REPORT-057-mono-anchor-and-settings-publish.md §4]` |
| `2f85141a74` | **引擎补丁 3**（脚本语言派生 + 编辑器开窗按节保存） | `[报告:REPORT-067-script-listing-and-editor-save.md §2]` |
| `e45ad638e6` | 三个引擎补丁的**净 diff 独立审计**锚点 | `[报告:REPORT-AUDIT-ENGINE.md]` |
| `4512d14c7e` | F-1（测试的配置独立性）**修复前**的测试文件 | 红相位重放的输入 `[报告:REPORT-071 §B.1]` |
| `9c12c2383` | **TASK-073 A** 的实现锚点（门③ 双精度可选变体） | `[报告:REPORT-073-double-gate-and-handover.md §0]` |
| `ff796dbf9` | TASK-072 的构建锚点（单精度/mono 二进制自报锚点） | 三个二进制的当前锚点（§1.5） |
| `b6fbb917b` | 本文写作时的 HEAD（TASK-073 A 的两个 `docs/**` 提交之后） | 本文所有现场核对的锚点 |

> **为什么 HEAD 比二进制新是正常的**：`9c12c2383` 之后到 HEAD 的提交**只动 `docs/**` 与 `scripts/**`
> （非编译输入）**，所以二进制**不需要重建**，其锚点对 HEAD 判 `ANCHOR_STRUCTURAL_EQUIVALENT`。
> 这正是 TASK-072 买来的性质 `[报告:REPORT-072-anchor-structural-equivalence.md §8]`。

### 0.3 相关的既有收口文档（本文不重复其内容，只链接）

| 文档 | 作用 | 锚点 |
|---|---|---|
| `docs/reports/MILESTONES-CLOSURE.md` | M0..M5 的**逐里程碑闭合清单**（含当时的三条非绿项归因） | 原文写于 `595607336d`，数字以原文锚点为准 `[报告:MILESTONES-CLOSURE.md §0.1]` |
| `docs/ACCEPTANCE.md` | M0 / M1 的**独立验收**记录（验收方是全新子代理） | M0 `57277407e7`、M1 `95dcb24c76` `[文件:docs/ACCEPTANCE.md:17,55]` |
| `docs/DESIGN-DETAIL.md` | 规范（GDR-1..GDR-28）：传输/JSON-RPC/端口/门/收窄/契约扩张 | 决策者维护，实现者只读 `[文件:docs/DESIGN-DETAIL.md:90,107,81,310]` |
| `docs/tasks/PLAYBOOK-group-port.md` | 每一组移植任务的**可复用任务书规范** | `[文件:docs/tasks/PLAYBOOK-group-port.md]` |
| `docs/reports/REPORT-073-double-gate-and-handover.md` | TASK-073 A（双精度变体）的完整报告 | `[sha:9c12c2383]` |

---

## 1. 交付物清单

### 1.1 工具：**176 条 = 171 移植 + 5 新增**

| 事实 | 数字 | 锚点 |
|---|---|---|
| 契约条数 | **176**（`_meta.count`） | `[契约:701539829ed8]`；`_meta` 里另含 `added_count=5`、`generator_version=1.20.0`、`order_normative=false` |
| 迁移源契约条目 | 174（`_meta.tool_count_in`） | 同上 |
| 下架（`unregister_until_implemented`） | 2：`navigate_to`、`export_project` | `_meta.excluded`；机器断言「这 2 个名字不在契约里」且**不被二次扣减**（字面量 103 是双重扣减，派生值 105） |
| 无损合并 | 1：`get_editor_performance` → `editor_get_performance_monitors` | `_meta.merged`；有损的两对**取消合并**并各自保留可区分名字 `[文件:docs/DESIGN-DETAIL.md:322-328]` |
| **移植总数** | **171** = 174 − 2 − 1 | `171 + 5 = 66 + 105 + 5: PASS`（现场实跑，见下） |
| 分批构成 | B1/B2 = **66**；B3/B4/B5 = **40 + 7 + 58 = 105**；新增 = **5** | 现场 `check_tool_groups.py --check-completeness`，退出码 0，`[sha:b6fbb917b]` |
| 端点可见性 | 编辑器 9888 = **153**；游戏 9889 = **72**；**并集 = 176**，`missing=0`、`foreign=0` | `[sha:e45ad638e6]` `[报告:REPORT-AUDIT-ENGINE.md §2.1 C0/C1/G2/G3/G4]`；`[sha:9c12c2383]` `[报告:REPORT-073 §3.2]` |
| scope 零泄漏 | 23 条 `scope=game` 不在 9888；104 条 `scope=editor` 全在 9888；`153 = 176 − 23` | `[报告:REPORT-AUDIT-ENGINE.md §2.1 C3/C4]` |
| 契约逐字门 | 9888 的 153 条与 9889 的 72 条**逐条** `name`/`description`/`inputSchema` **逐字相等**（canonical 比较） | 同上 §2.1 C2/G5 |

> **唯一一处非逐字节差异（已判为非缺陷）**：`editor_set_node_property_updates.inputSchema` 的 **JSON 成员顺序**
> 与契约不同，规范化后逐字相同。依据：契约 `_meta.order_normative=false`；门① 本身就是 canonical 比较；
> 源码注释写明「键序不是契约的一部分」（`tools/editor_node_property_updates.cpp:490-491`）
> `[报告:REPORT-AUDIT-ENGINE.md §2.1 末]`。

### 1.2 五个新增工具（`tool-groups-added.json`，8072 B，sha256 `0295cf86…`）

| 工具 | scope | channel | mutating | 锚点 |
|---|---|---|---|---|
| `project_build_csharp` | both | project | True | 现场 `--added` 实跑：`GROUP project_csharp_build channel=project scope=both mutating=True` `[sha:b6fbb917b]` |
| `project_write_text_file` | both | project | True | 同上 `GROUP project_text_write` |
| `project_validate_scripts` | both | project | **False** | 同上 `GROUP project_validate_scripts` |
| `editor_set_node_script_batch` | editor | editor | True | 同上 `GROUP editor_set_node_script_batch` |
| `editor_set_node_property_updates` | editor | editor | True | 同上 `GROUP editor_set_node_property_updates` |

- **清单与契约不能漂移**：`--added` 断言「manifest = 契约 `_meta.added_tools`，双向 `missing=0 foreign=0`」
  与「生成器版本三方一致（`GENERATOR_VERSION` / `_meta.generator_version` / `source.generator_version` = `1.20.0`）」
  `[sha:b6fbb917b]` 现场实跑。
- **拒绝面已独立验收**：20 条反例（`project.godot` / `.tscn` / `.gd` / `.cs` 覆盖、越界 `..`、已存在且
  `overwrite:false`、非标识符属性名 `glow_levels/1`、未知属性、plain 构建上的 C#）全部**同族拒绝**并给
  `data.suggestion`，没有一条「悄悄成功」`[报告:REPORT-AUDIT-ENGINE.md §2.2]`。
- **只有 1 个新增工具存在「Variant→类型化槽」写入**（`editor_set_node_property_updates`），它**过同一道
  `ValueSlot` 闸门**（`tools/tool_helpers.cpp:2410`）；其余 4 个按构造不存在该类写入
  `[报告:REPORT-AUDIT-ENGINE.md §2.4]`。

### 1.3 三个引擎补丁（**净改动只有 5 个引擎文件 / 752 增 / 7 删**）

净 diff 基线 `57277407e7` → 审计锚点 `e45ad638e6`：

| # | 目的（一行） | 文件:行（在 `b6fbb917b` 上核过） | 为什么必须动引擎 | 提交 |
|---|---|---|---|---|
| **①** | **让「这个 `.cs` 到底编译过没有」有真结论**：把 `_update_exports()` 里**本来就在做**的「源文件 mtime 晚于已加载程序集 mtime」比较，提升为一个**只读公开访问器**；`reload()` 的签名与语义**一字未动**，也没有加 `ClassDB` 绑定 | 声明 `[文件:modules/mono/csharp_script.h:294]`；定义 `[文件:modules/mono/csharp_script.cpp:2621]`；原调用点改为复用同一判据 `[文件:modules/mono/csharp_script.cpp:2174]`（旧文是内联的 3 行 mtime 比较） | 引擎侧**根本没有**「哪个文件、哪一行、什么错误」这一事实：C# 编译由 `GodotTools` 起的 `dotnet build` 完成，诊断只存在于 MSBuild 输出与插件的 csv 里；`CSharpScript::reload()` **无条件返回 OK**。若不补这一处，「未构建」与「编译失败」在引擎只是同形（dll mtime 不动）。项目级那一半由**模块自己**的 `project_build_csharp` 记录 | `[sha:5f3e7fb441]` `[报告:REPORT-055 §1.1,§2.1]` |
| **②** | **`ProjectSettings` 的「按节发布」**：新增 `save_custom_section()`（只重写目标节，其余文本逐字节复制），把「文本手术」整件搬进引擎 | 定义 `[文件:core/config/project_settings.cpp:1824]`；文本半部 `update_settings_section_text()` `[文件:core/config/project_settings.cpp:1558]`；读/写整文件 `[文件:core/config/project_settings.cpp:1714,1750]`；节集合发布 `publish_settings_sections_text()` `[文件:core/config/project_settings.cpp:1796]`；ClassDB 绑定 `[文件:core/config/project_settings.cpp:2268]`；头文件声明 `[文件:core/config/project_settings.h:249,269,274]` | 引擎既有的写出口 `save_custom()` 是**整文件重写**：手写注释全部丢失、键按引擎顺序重排。本模块曾有 5 个工具经它保存 `project.godot`。**上层文本拼接**被实测可行但**有 9 条风险**（R1 已复现的静默失败：`[input]` 非末节时键落错节、游戏读不到）→ 把按节写入做成引擎 API 是唯一「一次解决 R1–R9」的面 `[报告:REPORT-057 §4]`；补丁②在其提交里是**纯只增不改**（`+448/0`） | `[sha:96f631addb]` `[报告:REPORT-057 §4]` |
| **③** | **编辑器开窗保存不再吃注释**：开窗路径从整文件 `save()` 改为按节 `save_preserving_text()`；同批把「脚本语言集合」改为从 `ScriptServer` **派生**（模块侧 `tools/project_read_files.cpp`） | 调用点 `[文件:editor/editor_node.cpp:1085-1088]`（原先 `[文件:editor/editor_node.cpp:1071]` 的整文件 `save()`）；新增 `save_preserving_text()` `[文件:core/config/project_settings.cpp:1874]`，内部走 `publish_settings_sections_text()` `[文件:core/config/project_settings.cpp:1922,1935]` | 根因实测是一条链：`cmdline_mode = headless`（`editor_node.cpp:8479`）→ `if (!cmdline_mode)`（`:1062`）→ 整文件 `save()`（`:1071`，等价 `save_custom` → `_save_settings_text`）。所以 `--import`/`--headless` **不会**踩到、只有**窗口化编辑器**会吃注释，这也是它长期没被看见的原因。补丁③复用补丁②的文本半部，不再新造写出口 `[报告:REPORT-067 §2.1]` | `[sha:2f85141a74]` `[报告:REPORT-067 §2]` |

**非侵入性的完整判据（不是「看几处像改了」）**：`git diff 57277407e7..HEAD -- <5 个引擎文件>` 的 `-` 行
**总数** = `--numstat` 的 `3+0+1+3+0 = 7`，与报告里逐行列出的 7 行**逐行相等**，因此「没有第 8 处」由构造保证；
其中 3 行是纯搬家（`save_custom()` 头两行 + 空行）、3 行是**等价重构**（`_update_exports` 的 mtime 比较）、
1 行是**有意的调用点行为改进**（`:1071` 的 `save()`）。`reload()` 与 `ProjectSettings::save()` **完全未动**；
`save_custom()` 的签名与返回类型逐字不变 `[报告:REPORT-AUDIT-ENGINE.md §1.1–1.5]`。

**补丁②的正确性不是靠「只增」的措辞**：字节级实验（B0–B8）证明「旧路径仍整文件重写、仍丢注释」
（`project_remove_autoload`、无节名的 `project_set_setting` 回退路径）而「新路径只动目标节、注释 3→3 保留」
（`project_add_autoload`、有节名的 `project_set_setting`），且幂等（同一调用两次文件根本没被碰）
`[报告:REPORT-AUDIT-ENGINE.md §1.6]`。

### 1.4 HTTP / JSON-RPC 契约（规范：`DESIGN-DETAIL` §5 GDR-5 / §6 GDR-6）

| 项 | 规范（逐字取值见规范原文） | 锚点 |
|---|---|---|
| 端点 | `POST /mcp`；`GET /mcp` 回 200 + 状态 JSON（探活）；其它路径 **404**、其它方法 **405** | `[文件:docs/DESIGN-DETAIL.md:99]` |
| 监听 | `TCPServer::listen(port, IPAddress("127.0.0.1"))`——**只绑回环**，不得 `*`；连接上限 16，超出直接关新连接 | `[文件:docs/DESIGN-DETAIL.md:87,96-97]` |
| 头部/body | `Content-Length` **必需**（缺 → 411）；单头行上限 8 KiB；body 上限 `mcp_server.max_body_bytes` 默认 8 MiB → 超出 **413** 并关连接 | `[文件:docs/DESIGN-DETAIL.md:100-101]` |
| 响应 | `HTTP/1.1 <code> <reason>` + `Content-Type: application/json` + `Content-Length` + `Access-Control-Allow-Origin: *` + `Connection: keep-alive\|close` | `[文件:docs/DESIGN-DETAIL.md:102]` |
| keep-alive | 默认保持；空闲超 `mcp_server.connection_idle_seconds`（默认 30 s）关闭 | `[文件:docs/DESIGN-DETAIL.md:104]` |
| 方法 | `initialize`（`protocolVersion` `2025-03-26`、`serverInfo.name` `godot-mcp-rs`）；`notifications/initialized` → **HTTP 202 + 空 body**（不写 JSON）；`tools/list`（按 `scope` 过滤）；`tools/call`；`ping` → `{}` | `[文件:docs/DESIGN-DETAIL.md:111-117]` |
| 错误码 | `-32700` Parse error / `-32600` Invalid request / `-32601` Method not found / `-32602` 原始原因不加前缀 / `-32603` Internal error / `-32000` `No scene is currently open` + `data.suggestion` / `-32001` `<what> not found` + `data.suggestion` | `[文件:docs/DESIGN-DETAIL.md:123-126]` |
| `tools/call` 成功形状 | `{"content":[{"type":"text","text":"<工具结果的 JSON 字符串>"}]}`；若结果对象带 `console_output` 增量则并入 | `[文件:docs/DESIGN-DETAIL.md:116]` |
| `tools/call` 失败语义 | 有 `console_output` 增量 → **成功形状**，`content[0].text` 是 `{"error":…,"code":…,"console_output":[…]}`；否则返回 JSON-RPC 错误对象 | `[文件:docs/DESIGN-DETAIL.md:128-130]` |
| JSON 实现 | `JSON::parse_string` / `JSON::stringify`，`sort_keys=true`（= 参考实现 serde_json 的有序键）；**对等门比的是解析后的结构**，但 `inputSchema` 内的键名必须逐字一致 | `[文件:docs/DESIGN-DETAIL.md:132-134]` |
| `id` 保真 | `initialize`/`tools/call` 的 `id` 允许 string/number/null，**必须原样回带**；`id: true` 等非规范类型也原样回显（GDR-12 的宽松行为**写入规范**） | `[文件:docs/DESIGN-DETAIL.md:109,265]`；`[文件:docs/ACCEPTANCE.md:100]` |
| 端口解析（GDR-4） | ①`--mcp-port=N`/`--mcp-port N` ②`ProjectSettings: godot_mcp/port` ③默认 `Engine::is_editor_hint() ? 9877 : 0`（**游戏侧 0 = 不监听**，需显式 `--mcp-port` 或 `godot_mcp/enabled_in_game=true`） | `[文件:docs/DESIGN-DETAIL.md:83-88]` |
| 绑定失败 | **不得崩溃**：写 `WARNING` `[MCP] bind failed …` 并禁用服务，`get_port()` 返回 0 | `[文件:docs/DESIGN-DETAIL.md:88]`；游戏侧真实签名的现场记录 `[报告:BREAKOUT-FINDINGS-R3.md:253]` |

> **端口归属（移交时最要紧的一条）**：**9877 属于用户**（正在使用的 4.7.1-mono 编辑器）。
> 本模块的一切自动化**只用 9888（编辑器）/ 9889（游戏）**；`mcp_port_guard.ps1` 负责分类观测，
> 门脚本断言 `pid_before == pid_after == -1` 且 `asked_by_us=False`
> `[文件:docs/tasks/PLAYBOOK-group-port.md:96-97]`、`[报告:REPORT-071 §C.2 G230/G231]`。

### 1.5 构建：mono 与非 mono（外加一个双精度变体）

**三个变体，产物名、对象缓存互不干扰**（`SConstruct:1051-1053,1171-1173` 给 `precision=double` 加 `.double` 后缀）：

| 变体 | 构建命令（**从 cmd 启动**） | 产物 | 判定 | 当前自报锚点 `[sha:b6fbb917b]` |
|---|---|---|---|---|
| **plain（非 mono）**：默认门用的那个 | `modules\mcp_server\scripts\build_local.cmd -Force`（= `scons platform=windows target=editor module_mono_enabled=no tests=yes -j8`） | `bin\godot.windows.editor.x86_64.console.exe` | 自报锚点 `ff796dbf9` 对 HEAD `b6fbb917b` = **`ANCHOR_STRUCTURAL_EQUIVALENT`**（64 个安全差异、**0 红**） | 现场实跑（§4 步 2） |
| **mono**：C# 成功腿与 `project_build_csharp` 需要它 | ①`modules\mcp_server\scripts\mcp057_build_mono.cmd`（= `… module_mono_enabled=yes tests=yes -j8`）②`python modules\mono\build_scripts\build_assemblies.py --godot-output-dir=bin --godot-platform=windows` | `bin\godot.windows.editor.x86_64.mono.console.exe` | 同上：`ff796dbf9` → **`ANCHOR_STRUCTURAL_EQUIVALENT`**（64/64 安全、0 红） | 现场实跑（§4 步 2） |
| **double（可选变体，opt-in）** | `modules\mcp_server\scripts\mcp070_build_double.cmd`（= `… precision=double tests=yes -j8`） | `bin\godot.windows.editor.double.x86_64.console.exe` | `9c12c2383` → **`ANCHOR_STRUCTURAL_EQUIVALENT`**（34/34 安全、0 红）；冷构建约 15 min，热约 63 s | 现场实跑（§4 步 2）；`[报告:REPORT-073 §4.3]` |

- **为什么必须走仓库里的 `.cmd`**：仓库根的未跟踪脚本 `build-m0.cmd` **不传 `tests=yes`**，`--version` 校验会通过
  但 `--test` 会**直接 abort**（M4 验收已踩到）`[文件:docs/tasks/PLAYBOOK-group-port.md:105-107]`。
- **改动 `tests/*.h` 后必须 `-Force`**：scons 对 `tests/test_mcp_server.h` **没有依赖边**（`modules/SCsub:55` 经
  `CommandNoCache` 生成 `modules/modules_tests.gen.h`），不删陈旧对象就会静默跑**旧用例** = 假绿
  `[文件:modules/mcp_server/scripts/build_local.cmd:19-33]`。
- **切变体后必须重建 `mcp_trace` 对象**：`core/version_generated.gen.h` 的 `GODOT_VERSION_MODULE_CONFIG`
  带 `.mono`/空，scons 不会因它重建，会让追踪标记写错的变体名 `[文件:scripts/mcp057_build_mono.cmd:24-29]`。
- **构建严格串行（D62）**：两个并发 scons 会同时重写 `modules/modules_tests.gen.h`，产生一批与本批无关的
  假编译错误；且**杀后台任务不保证其 scons 子进程死**。输出**不得经管道**（管道会把退出码交给错误的进程），
  三个 `.cmd` 都落盘 `%TEMP%` 日志并**同时**回显 `[文件:docs/tasks/PLAYBOOK-group-port.md:117-119]`。

---

## 2. 门与纪律

### 2.1 六道门

| 门 | 命令 | 通过标准 | 最近实测与锚点 |
|---|---|---|---|
| **① 契约子集逐字** | `powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\check_contract_subset.ps1`（`-Group <组名>` 可只查一组） | 实况 `tools/list` **等于** `tool-groups.json` 中所有 `implemented=true` 组的**并集**；9888 与 9889 上各条 `name`/`description`/`inputSchema` **逐字 True**；任何「未实现却已注册」都失败 | **3/3 PASS，exit 0**；`contract=176`；`implemented_union = 153 (editor) / 72 (game)`；`guard_user_port_9877 pid_before=-1 pid_after=-1` `[sha:9c12c2383]` `[报告:REPORT-073 §3.2]`；证据 `EV72/gate1_contract_subset.txt` |
| **② 三类证据（活）** | `powershell … -File modules\mcp_server\scripts\mcp071_gate2_live_evidence.ps1` | 每个工具（或按「非工具批次」的对应物）：**成功 / 缺参 / 底层失败**各一组真实请求–响应；**外加一条跨工具端到端活证据链**；哪一类不可构造必须显式声明原因 | **14/14 PASS，exit 0**；编辑器 `tools/list` 153 条（61 863 B，sha256 `333b4a6858aa…`）、游戏 72 条（32 973 B，`0ed732aff616…`）、并集 176 = 契约 176；`-32602`、`-32001 + data.suggestion`；链 `project_create_script → project_read_script → project_validate_script` `[sha:ff796dbf9]` `[报告:REPORT-072 §5]`；证据 `EV71/gate2_live_evidence.txt`、`EV72/gate2_live_evidence.txt` |
| **③ 模块 doctest（默认 = 单精度门）** | `bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="[MCPServer]*"` | 全绿，**只允许增加** | **345 / 345 passed / 0 failed / 1429 skipped；23 971 / 23 971 assertions** `[sha:9c12c2383]` `[报告:REPORT-073 §3.2]`；**它是单精度门**——见 §3(b) |
| **③′ 双精度变体（opt-in）** | `powershell … -File modules\mcp_server\scripts\mcp059_gates.ps1 -PrecisionVariant double`（等价 `-WithDouble`） | 在**默认 22 步之后追加一步** `gate3_double_variant`：串行构建 `.double.` → 判锚点（`ANCHOR_EQUAL`/`ANCHOR_STRUCTURAL_EQUIVALENT` 通过，`ANCHOR_STALE_COMPILED` **必须红**）→ 同一用例集全绿 | 双精度 **345/345、23 956 assertions**；锚点 **`ANCHOR_EQUAL`**；构建 63.8 s + doctest 14.4 s；**默认不给开关时步数 22、结果与时长逐项不变、不构建**（双精度产物 5/5 行 `LastWriteTimeUtc|Length` 逐字节未变）`[sha:9c12c2383]` `[报告:REPORT-073 §3.3,§4]`；证据 `EV73/gate3_double_summary.txt`、`EV73/gate3_default_plan_compare.txt` |
| **④ 全引擎回归** | `bin\godot.windows.editor.x86_64.console.exe --headless --test` | **0 failed**；passed 只允许因新增测试增加 | **1771 / 1771 passed / 0 failed / 3 skipped；448 218 / 448 218 assertions** `[sha:9c12c2383]` `[报告:REPORT-073 §3.2]`；证据 `EV71/doctest_full_engine.txt`、`EV72/gate4_full_engine.txt` |
| **⑤ 每批收口：`accept_m1` ×2 + 清单一致** | `powershell … -File modules\mcp_server\scripts\mcp056_regression_battery.ps1` | 两次都全过，且两次 **PASS 清单逐字节一致** | **23/23 ×2**，`accept_m1_pass_lists_agree \| 0 \| differing_lines=0` `[sha:9c12c2383]`/`[sha:ff796dbf9]` `[报告:REPORT-072 §5]`；该电池同时快照并**按声明**还原被跟踪证据 `[文件:scripts/mcp056_regression_battery.ps1:16-31]` |
| **⑥ 收窄点清单（三段式，GDR-24）** | ①`python modules\mcp_server\scripts\check_narrowing_points.py` ②`… --coverage` ③`powershell … -File modules\mcp_server\scripts\mcp031_gate6_coverage_probes.ps1` | 三段都 **exit 0**：`scanned == pinned`、0 误报、集合内**每一种拼写**都有「插入即 exit 1」探针、探针后逐字节还原 | 现场实跑 `[sha:b6fbb917b]`：①`scanned=75 pinned=75`（16 个文件）exit 0，②打印 **17 种已声明拼写**，③其历史实测 **101/101 PASS** `[sha:9c12c2383]` `[报告:REPORT-072 §5]`；证据 `EV72/gate6a_narrowing.txt`、`EV72/gate6c_probes.txt` |
| （附）**生成器三连** | `python modules\mcp_server\docs\scripts\check_tool_groups.py --check-completeness` / `--added` / `--generator-version` | 三个都 **exit 0**，并断言契约条数 **176 不变** | 现场实跑 `[sha:b6fbb917b]`：三个 PASS；`BYTES ADDED 8072`、`SHA256 ADDED 0295cf86…`、`GENERATOR-VERSION 1.20.0`、`171 + 5 = 66 + 105 + 5: PASS` |
| （附）**一次跑完并集电池** | `powershell … -File modules\mcp_server\scripts\mcp059_gates.ps1` | 22 步全部 `exit=0`，收尾 `ALL GATE STEPS EXIT 0` | **22 步全 exit 0**（不给开关）`[sha:9c12c2383]` `[报告:REPORT-073 §3.2]`；证据 `EV73/battery_default_summary.txt` |

> **门必须先绑定构建（流程风险 R-1）**：`bin/` **不受版本控制**（`.gitignore` 忽略 `[Bb]in/`），
> 门会在**陈旧二进制**上跑出假红。每批开跑门之前必须：①重建；②用**唯一判据**校验锚点（见 §4 步 2）
> `[文件:docs/tasks/PLAYBOOK-group-port.md:99-103]`。

### 2.2 门完整性六条纪律（每条：它防的是什么 + 反例演示脚本路径）

| # | 纪律 | **一句话：防的是什么** | 实现 / 谁调用 | **反例演示脚本路径** | 锚点 |
|---|---|---|---|---|---|
| 1 | **恒真断言** | 防「一个永远不可能失败的检查被当成一道门」——`-or $true`、`if ($false)`、`assert True` 这类拼写会让门在什么都不验的情况下变绿 | `modules\mcp_server\scripts\check_tautologies.py`（`mcp059_gates.ps1:125-127` 三步：scan / `--probes` / `--coverage`） | 检查器自带的插入探针 `check_tautologies.py --probes`（**18/18**：14 种已声明拼写 + 4 个 near-miss）；真实缺陷演示 `modules\mcp_server\scripts\mcp059_d2_failure_demo.ps1`（**旧的恒真谓词只能永远 exit 0**，人为制造残留后必须 exit 非零） | 现场实跑 `[sha:b6fbb917b]`：scan `TAUTOLOGY CHECK PASS` exit 0、`PROBES: 18/18` exit 0、`DECLARED SPELLINGS : 9 powershell + 5 python`、`PINNED: 1`；`[报告:REPORT-059 §4.1]`、`[报告:REPORT-AUDIT-ENGINE.md §3.1]` |
| 2 | **假等待** | 防「开发还没结束就收工、却把一轮不完整的观察读成观察完成」——停止条件必须是**机器可核对**的 | `modules\mcp_server\scripts\mcp_watch_run.ps1`（`stop_reason ∈ {marker,timeout,stale}`；`reason != marker` 时**额外**写 `observation_stopped_before_development_ended=1`） | `modules\mcp_server\scripts\mcp065b_watch_invocation_probe.ps1`（调用姿势探针，仍回 `stop_reason`）；五情景反例 `EV61/s1-marker`、`s2-timeout`、`s3-stale`、`s4-counterexample`、`s5-old-protocol`（旧协议 stdout 只有 1 个裸 LF、全文不含 `stop_reason`） | `[sha:ea345b51df]` `[报告:REPORT-061 §3,§8]`（交付提交 `ea345b51df…`，开工基线 `0a9fc1d466`）；`[报告:REPORT-AUDIT-ENGINE.md §3.4]`（我自建观察者反例：开发中 → `timeout`/`stale`，只有真的 marker 叶子文件 → `marker`，同名**目录**冒充 → `timeout`） |
| 3 | **静默覆写证据** | 防「一个步骤把别人刚写下的产物改了/删了，而门仍然报 PASS」——还原必须**按声明**、**默认拒绝** | `modules\mcp_server\scripts\mcp_evidence_guard.ps1`（`Get-McpEvidenceState` / `Restore-McpEvidence` / `Test-McpDeclaredPath`；`mcp056_regression_battery.ps1:56,131,186-187,197` 声明 `-AllowedPaths`/`-AllowedRoots`，`:237` `exit 1`） | `modules\mcp_server\scripts\mcp069_guard_whitelist_probe.ps1`（**13/13 PASS**：W10–W12 未声明文件原样存活、W13–W15 声明文件真的被还原/删除、W20–W23 **完全不给声明时一个路径都不动**、W24 声明 `./` 抛异常被拒、W25/W27 前缀规则而非子串）；覆盖面探针 `mcp071_guard_inventory_probe.ps1`（**17/17**）、`mcp070_guard_blindspot_probe.ps1`（**10/10**） | `[sha:e45ad638e6]`（whitelist probe）`[报告:REPORT-069 §1.6]`；`[sha:4512d14c7e]`（inventory / blindspot 探针）`[报告:REPORT-071 §A.4,§C.4]`；证据 `EV71/probe_mcp071.txt`、`EV71/probe_mcp070_second_edition.txt` |
| 4 | **删证据（电池路径白名单）** | 防「回归电池把自己见过的**未跟踪**文件全部删掉」——那不是还原，是清扫；它曾删掉同批另一位工程师正在写的报告 | 同上一行的守卫（白名单语义：声明外只报告不动；裁决只对**声明集合**说话） | `mcp069_guard_whitelist_probe.ps1` 的同一批用例（尤其 W10–W12「未声明的 `REPORT-planted.md` 原样存活、sha256 不变」与 W20–W23「默认拒绝」） | `[报告:REPORT-069 §1]`（改动前的真实电池复现）`[报告:REPORT-069 §1.3-1.5]`（改法 + 同场景修复后文件仍在） |
| 5 | **内红必须非零** | 防「门打印了 FAIL / 内部有红色步骤，进程却 **exit 0**」——一条红色被 summary 打印出来就等于被消化掉了 | `modules\mcp_server\scripts\check_exit_propagation.py`（**唯一挂在 `accept_m1.ps1` 里的那一条**：`case0_repo_exit_code_propagation`，而 `accept_m1` 是「每批必跑两次」的接受电池） | `modules\mcp_server\scripts\mcp069_exit_propagation_demo.ps1`（**三条腿**：`unguarded` summary 里带 `EXIT 3` 而进程 exit 0；`guarded_red` 同一输入 + 真实 guard 文本 → **exit 1**；`guarded_green` → exit 0）；陈旧期望反向探针 `mcp069_stale_expectation_reverse_probe.ps1`；检查器自带探针 `check_exit_propagation.py --probes` | 现场实跑 `[sha:b6fbb917b]`：`EXIT-CODE PROPAGATION CHECK PASS` exit 0、`PROBES: 10/10` exit 0、`DECLARED SHAPES : 2 powershell + 1 python` / `DECLARED GUARDS : 10 powershell + 6 python` / `PINNED: 2`；`[报告:REPORT-AUDIT-ENGINE.md §3.2]`；证据 `EV72/check_exit_propagation.txt` |
| 6 | **锚点不得假红** | 防「二进制并非陈旧（只领先了几个 `docs/**`/`scripts/**` 提交），门却把 `--version != HEAD` 判成红」——**假红会腐蚀对门的信任**，比假绿更难发现 | **唯一判据** `modules\mcp_server\scripts\check_engine_anchor.ps1`（库模式 + 命令模式；四种 verdict：`ANCHOR_EQUAL`/`ANCHOR_STRUCTURAL_EQUIVALENT` = PASS，`ANCHOR_STALE_COMPILED`/`ANCHOR_NOT_ANCESTOR` = FAIL；未分类后缀一律红，fail-closed）；15 个脚本**只调用它、没有第二份判据** | `modules\mcp_server\scripts\mcp072_anchor_counterexample_probe.ps1`（在**真实仓库**用临时提交构造：只改 `.md` → **不红**；改 `.cpp` → **STALE 红**；非祖先/伪造 sha → **NOT_ANCESTOR 红**；真重建 → **EQUAL**；`finally` 里 `reset --hard` 并断言 HEAD/porcelain/两文件 sha256 回位）；判据自身的决策表探针 `mcp072_anchor_judge_probe.ps1`（**13/13**，含 `config.py` 红、未分类后缀红、侧分支 NOT_ANCESTOR、无 token NOT_ANCESTOR） | 现场实跑 `[sha:b6fbb917b]`：三个二进制全部 `ANCHOR_STRUCTURAL_EQUIVALENT` + `RESULT PASS` exit 0（plain/mono `DIFF_COUNT=64 SAFE=64 RED=0`；double `34/34/0`）；`[报告:REPORT-072 §1,§3,§4]`；证据 `EV72/counterexample_probe.txt`、`EV72/judge_probe.txt`；`STALE` 真反例 `EV73/anchor_stale_compiled_probe.txt` |

> **一条结构性观察（不是阻塞缺陷，但接手人必须知道）**：六条纪律**没有全部收敛到同一个 CI 入口**。
> `check_exit_propagation.py` 挂在 `accept_m1.ps1`；`check_tautologies.py` 在 `mcp059_gates.ps1`；
> 证据守卫在 `mcp056_regression_battery.ps1`；观察者在 breakout/观察者脚本里；锚点判据被 15 个脚本**调用**。
> 所以**只跑 `accept_m1` 变绿不能推出另外几条生效**——要按 §4 的清单逐条跑
> `[报告:REPORT-AUDIT-ENGINE.md §3.0 观察,§5 risks R-1]`。

### 2.3 其它硬性纪律（承接 PLAYBOOK §5 / §7）

| 纪律 | 内容与理由 | 锚点 |
|---|---|---|
| 只改 `modules/mcp_server/**` | 其它一切（引擎其它目录、`godot_mcp_gdext`、**整个 hof-rs 仓库**）**只读** | `[文件:docs/tasks/PLAYBOOK-group-port.md:164]` |
| 不注册未实现的工具 | 门① 的并集断言会因此失败；`fix_implementation_first` 必须先写红测试证明缺陷再修 | `[文件:docs/tasks/PLAYBOOK-group-port.md:165-168]` |
| 不许伪造输出 | 之后有**全新子代理**独立验收；证据被证伪要**撤回并标注**（append-only 勘误） | `[文件:docs/tasks/PLAYBOOK-group-port.md:170,225-226]` |
| 证据采集 | 一律 `curl.exe -s -o <file>` 落盘（**禁止 `Out-File`/管道承载响应体**，曾把每个非 ASCII 字符塌成 `?` 导致独立验收判 fail）；比较前先算 sha256 | `[文件:docs/tasks/PLAYBOOK-group-port.md:218-220]` |
| 「工具是否在线」判定 | **禁止** `-match`/文本包含——`description` 会互相按名引用；必须解析 `tools/list` 的 `name` 做集合判断 | `[文件:docs/tasks/PLAYBOOK-group-port.md:227-230]` |
| `REQUIRE` 不中止用例 | 本 harness 的 doctest `REQUIRE` **不会中止**（`tests/test_macros.h:44`）→ `REQUIRE` 之后的每次读取/索引都要自己守卫，否则以「读到空值」的形式产生**假绿** | `[文件:docs/tasks/PLAYBOOK-group-port.md:233-234]` |
| `.ps1` 纯 ASCII | 中文乱码/编码是已发生过的证据污染来源；脚本一律纯 ASCII，文档才写中文 | `[文件:docs/tasks/PLAYBOOK-group-port.md]`（各批纪律清单） |
| 工作树收尾 | 只应剩既有未跟踪物：`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd` | `[文件:docs/tasks/PLAYBOOK-group-port.md:171]`；现场 `git status --porcelain` `[sha:b6fbb917b]` |

---

## 3. 已知边界与已声明限制（**移交最重要的一节，完整列 10 条**）

> 这一节的作用是防止「把有界保证当成证明」。每条都写明**它保证什么、不保证什么、锚点在哪**。

### (a) `rationale` / `scope` 等**已声明的语义**是「声明」，不是「被判定的行为」

- **保证**：`scope` / `channel` / `mutating` / 版本串等**声明**有机器检查——批量清单的不变式（一组一 channel、
  一 scope、一 mutating、≤10 个工具、每个工具恰好一次）+ 与契约 `_meta.added_tools` 的双向相等 + 生成器版本三方相等。
  现场 `check_tool_groups.py --added --generator-version` 全 PASS `[sha:b6fbb917b]`。
- **不保证**：这些字段的**语义**不由引擎判定。「5 个新增工具里只有 1 个真的过 `ValueSlot` 闸门」是靠
  **代码腿逐条读源码**得出的，不是机器断言 `[报告:REPORT-AUDIT-ENGINE.md §2.4]`。
- **`rename-map` 的 `reason`（rationale）**：其中的源码引用指向**迁移源**（`godot_mcp_gdext`/`addons`），
  **不因 C++ 重写而改写**（改写会动映射 sha → 文档指纹 → 契约 `_meta.map_sha256`）；**它不再是行为依据**，
  有分歧时以**契约描述**为准（已有一例：`editor_analyze_signal_flow` 的 `flags & 1` 残留）
  `[文件:docs/tasks/PLAYBOOK-group-port.md:183-184,201-202]`。
- **`_meta.order_normative = false`**：JSON **成员顺序不是契约的一部分**，门用 canonical（键排序）比较
  `[契约:701539829ed8]`、`[报告:REPORT-AUDIT-ENGINE.md §2.1]`。
- **(a′) 已声明的有损语义**（描述里写明，不是静默）：`project_remove_autoload` 仍走整文件写者，描述里逐字写着
  `every hand-written comment in that file is lost`；无节名的 `project_set_setting` 同理回退整文件
  `[报告:REPORT-AUDIT-ENGINE.md §1.6 B4/B5/B6]`。

### (b) **门③ 默认是单精度门**；双精度是**可选变体**

- 门③ 跑的是 `bin\godot.windows.editor.x86_64.console.exe`，即 `precision` 缺省（`float`）。
- `-PrecisionVariant double` / `-WithDouble` 才**追加一步**（串行构建 → 判锚点 → 同一用例集全绿）；
  **不给开关时步数、结果与默认时长逐项不变、不构建任何东西**（双精度产物 5/5 行逐字节未变）
  `[sha:9c12c2383]` `[报告:REPORT-073 §2,§3.3,§4]`。
- 两个开关**互相矛盾时是 usage error（exit 3）**，不是「后者静默胜出」`[文件:scripts/mcp059_gates.ps1:72-77]`。
- 口径已写进 PLAYBOOK §3 门③ 那一行 `[文件:docs/tasks/PLAYBOOK-group-port.md:64]`；**`DESIGN-DETAIL` 未改**
  （决策者才有权改），建议文本在 `[报告:REPORT-073 §6]`。

### (c) 证据守卫**只能发现未跟踪文件被删/被改，不能还原**

- `MISSING-UNTRACKED` / `CHANGED-UNTRACKED` 只是**把静默换成点名**：被删/被改的字节**不在 git 里**，
  还原之后文件**仍然不在** / **仍是新字节**（`W11`/`W13`，检查 id `g_blindspot_a/b_is_detected_but_NOT_restored`）。
  唯一**可还原**的是 `APPEARED-UNTRACKED`（删除），且**仅当路径被声明**；未声明的一律 `UNTOUCHED`
  `[报告:REPORT-071 §A.5]`。
- **只看得见 `git status` 看得见的东西**：`.gitignore` 覆盖的路径（`bin/`、`.godot/`、`*.log`）在这套机制之外
  ——现场证明：电池自己的 15 份步骤 `.log` 全部被 `*.log` 忽略，所以 `appeared-untracked=4` 而不是 ~22
  `[报告:REPORT-071 §A.8]`。
- 默认模式会被「**等长且同 tick**」的改写骗过（`W17` 实测 0 行）；要内容级保证需开 `-HashUntracked`
  （成本 ~2.8×：本仓 4026 个未跟踪文件时 2 336 ms → 6 587 ms）`[报告:REPORT-071 §A.4]`。

### (d) 恒真/退出传播检查是**拼写可见的有限集合**（集合外的写法能逃）

- `check_tautologies.py` 声明 **14 种拼写**（9 PowerShell + 5 Python）；把同一个常数写成**集合外**拼写
  （例如裸 `($true)`）时脚本 **exit 0 且不点名**——这正是脚本 docstring 声明的边界
  `[文件:scripts/check_tautologies.py:34-38]`、`[报告:REPORT-AUDIT-ENGINE.md §3.1 ⚠️]`。
- `check_exit_propagation.py` 同理：一个「打印 `FAIL` 字样、但不含任何已声明聚合形状」的文件**不会被抓**；
  而「在死代码里、`exit` 之后、没人调用的函数里」的形状**也不在检测面内**
  `[文件:scripts/check_exit_propagation.py:33-39,51-54]`、`[报告:REPORT-AUDIT-ENGINE.md §3.2 ⚠️]`。
- **门⑥ 同族**：它只看得见**拼写可见**的收窄（17 种已声明拼写，现场 `--coverage`；PLAYBOOK 里写的「16 种」
  是**陈旧的较小数字**——以脚本 `--coverage` 打印的 17 为准）。运行时把 `double` 隐式写进 `real_t`/`float`、
  整数收窄、集合外拼写都在门外，必须靠**代码审查 + 行为证据**两条腿补
  `[文件:docs/tasks/PLAYBOOK-group-port.md:78-93]`、`[文件:docs/DESIGN-DETAIL.md:721-757]`。
- **编译器级检查不可用（已实测否决）**：MSVC `/we4244` 无法只作用于 `modules/mcp_server/**`——本模块的翻译单元
  会包含引擎头（`core/math/*.h`、`core/string/ustring.h`、`core/typedefs.h`），这些头本身大量触发 C4244，
  `SConstruct` 全局 `/wd4244` 的注释正是「Unavoidable at this scale」；升为错误会让构建在**不许改的引擎代码**上失败
  `[报告:REPORT-031-gate6-coverage.md §2]`。

### (e) watcher **不校验 marker 的写入者**

- `mcp_watch_run.ps1` 的完成判据是「marker 路径上存在一个**叶子文件**」（`Test-Path -PathType Leaf`，
  顶住了「同名目录冒充」）。它**不校验 marker 的内容或写入者**：任何进程只要创建那个叶子文件就能让它判 `marker`
  ——这是**有意设计**（确定性的停止条件），不是绕过缺陷 `[报告:REPORT-061 §2/§3]`、`[报告:REPORT-AUDIT-ENGINE.md §3.4 ⚠️]`。
- 该纪律的**实质保证**是：想「开发还没结束就收工」，只能得到 `timeout` 或 `stale`；而且 `reason != marker` 时
  产物里**强制**多写一行 `observation_stopped_before_development_ended=1`，让「被强制停止」无法被读成观察完成
  `[文件:scripts/mcp_watch_run.ps1]`（用法与输出见 `[报告:REPORT-061 §2]`）、`[报告:REPORT-061 §3.5]`。

### (f) `unverifiable` / `language_unavailable` / `not_compiled` 三类的**语义区别**

三个都是「**不声称**」（`valid` 不发布，线上是 `null`），但**理由完全不同**——混淆它们就是撒谎：

| 分类 | 含义（它说的是什么） | `valid` | 单数工具的形状 | 锚点 |
|---|---|---|---|---|
| `language_unavailable` | **本构建没有该扩展名的脚本后端**（`ScriptServer::get_language_for_extension()` 为空，例如 `module_mono_enabled=no` 的 `.cs`）。这是**构建的属性**，不是对该文件的判决 | **`null`**（D1 修复后**不得**再发 `valid:false`；`false` 会被读成「文件编译失败」） | `-32000` + `data.suggestion`（点名该用哪个构建） | `[文件:tools/project_read_files.cpp:566-573]`；`[报告:REPORT-056-audit-added-d1-fix.md §1]`；`[报告:REPORT-AUDIT-ADDED-B.md §①]` |
| `unverifiable` | **引擎根本没能把该文件当 `Script` 载入**——TASK-055 之后这是**唯一残余情形**（旧口径「C# 没有结论」已被真结论**作废**） | `null` | `-32000` + `data.suggestion` | `[文件:tools/project_read_files.cpp:403-411,508-511,637-638]` |
| `not_compiled` | **没有任何构建编译过这段源码**：文件在已加载的 .NET 程序集构建之后被改过（`is_source_newer_than_assembly()` 为真），或已加载程序集里根本没有该脚本路径的类。**刻意不是 `invalid`**——引擎没有 C# 编译器，`CSharpScript::reload()` **无条件返回 OK** | `null`（`false` 会被读成「不编译」） | `-32000`，message 明说 `no build of this source is loaded…`；`data.suggestion` 逐字含 **"This is 'not compiled', which is not 'does not compile'"** 并指名 `CSharpScript::is_source_newer_than_assembly()` | `[文件:tools/project_read_files.cpp:426-455,532-539,681-683]`；`[报告:REPORT-055 §3 ①]`、`[报告:REPORT-066-csharp-breakout.md:105]` |

**判据（可执行）**：
- 批量的 `count` **恒等于**五类计数器之和（`ok`/`invalid`/`not_compiled`/`language_unavailable`/`unverifiable`），
  且等于实际被问的文件数；`valid` **只**对 `ok`/`invalid` 发布
  `[文件:tools/project_validate_scripts.cpp]`、`[报告:REPORT-056 §③]`。
- **强证据**：`invalid` 与 `not_compiled` 曾在**同一响应**里并存（`count=2 invalid_count=1 not_compiled_count=1`，
  两条 item 分别带 `error CS0103` 原文与 `valid:null`）`[报告:REPORT-055 §3]`、`[报告:REPORT-066-csharp-breakout.md:106]`。
- **诚实边界（必须与结论同读）**：`invalid` 只有在**本会话真的跑过一次** `project_build_csharp` 之后才可能出现；
  没有那次构建，工具**只能**答 `not_compiled`。**不得**把「工具能自己编译 C#」写成结论
  `[报告:REPORT-055 §3 代价]`、`[报告:BREAKOUT-FINDINGS.md:199 P2g]`。
- **已知陷阱**：`Godot.NET.Sdk` 的 `ScriptPathAttributeGenerator` 对「文件名 == 类名」**大小写敏感**；
  不符时的症状是 **`not_compiled` 而不是编译错误**，容易误判为缺陷
  `[报告:REPORT-055 §8]`、`[报告:BREAKOUT-TEST-PLAN.md:113]`。
- **`unverifiable` 的线上实例至今未构造**（`ResourceLoader.load` 对可读 `.cs` 总能返回 `CSharpScript`）；
  它的文案与拒绝形状由 doctest 逐条断言覆盖——**不记为通过**
  `[报告:REPORT-055 §3 不可构造]`、`[报告:REPORT-AUDIT-ADDED-B.md §10]`。

### (g) `project_list_scripts` **会列出 `.godot` 生成脚本**（已声明，不收窄 walk）

- 该工具的枚举谓词自 TASK-067 起**从 `ScriptServer` 派生**（构建注册了什么语言就列什么扩展名，
  `.gdshader` 作为唯一的非 `ScriptLanguage` 例外保留）；但 **walk 本身一字未改**：只跳过 `.` 与 `..`，
  因此 `.godot`、`.hidden*`、`addons` 都下钻 `[文件:tools/project_read_files.cpp:215-239]`、`[报告:REPORT-067 §1.3]`。
- **已发布的后果**：真实 mono 工程里**构建生成**的 `.cs` 也会被列出（本批实测 2 条：
  `res://.godot/mono/temp/obj/Debug/.NETCoreApp,Version=v8.0.AssemblyAttributes.cs`、
  `…/McpBreakoutCs.AssemblyInfo.cs`）`[报告:REPORT-067 §1.4]`。
- **契约描述里已如实写明**（走 `DESCRIPTION_OVERRIDES` 的 append 子句，生成器 v1.20.0），因此这是
  **已声明的行为**而不是文档缺口 `[报告:REPORT-068 §2.2]`、`[契约:701539829ed8]`（`project_list_scripts.description`）。
- **为什么不在本批收紧**（两个硬约束）：(a) 收紧 `res://.godot` 会改动参考实现声明过的跳过规则，而
  `.hiddendir/secret.gd` 必须仍被收集——这条断言是**已发布证据的一部分**（`tests/test_mcp_server.h:2991` 的
  `expected` 含 `project.path(".hiddendir/secret.gd")`）；(b) 把「哪个目录是生成物」写进工具需要一个**新的、
  机器可验证的判据**，不能顺手塞进去 `[报告:REPORT-068 §2.2,§6.3]`。
- **该工具的「缺参」类不可构造**（契约 `inputSchema = {"properties":{},"required":[],"type":"object"}`，
  结构上没有参数）——已显式声明 `[报告:REPORT-068 §5.3]`。

### (h) **一次未归因的间歇 `0xC0000005`**（首次 `--import`，第二次成功）

- 现象：`--import` 可能以 `0xC0000005`（退出码 `-1073741819`）结束，并把工程留在**半导入**状态——
  此后的每一条断言都在错的输入上跑，**而门仍可能全绿** `[文件:docs/tasks/PLAYBOOK-group-port.md:132-139]`。
- **归因结论（覆盖旧记载）**：TASK-028 用 7 个变体 × 6 次全新工程首导（含/不含 `.tscn`、`.tscn` 带/不带 BOM、
  `project.godot` 带 BOM、含 `ext_resource`、`--mcp-port` 缺省/`=0`/`=9888`）共 **84 次全部 exit 0**，
  `Parse Error` 一次未现。因此「`.tscn` 带 BOM 必崩」「含 `.tscn` 的新工程首次必崩」**都不成立**；
  历史记载（PLAYBOOK 旧文、`REPORT-027`、`mcp016` 注释）是**间歇性引擎侧崩溃**：本项目历史上出现过 4 次
  （M3 / mcp016 / mcp026 / mcp027），TASK-028 **无法复现、也无法归因到本模块**
  `[文件:docs/tasks/PLAYBOOK-group-port.md:140-147]`、`[报告:REPORT-028-subpaths-clear-import.md]`。
- **因此纪律不依赖「哪个变体触发它」**，而依赖三件无条件正确的事：①**退出码必须校验**；
  ②**有界重试**（默认 3 次）；③**每次失败都打印命令、退出码、工程路径、日志路径与日志尾部**——
  共享助手 `scripts\mcp_import_guard.ps1` 的 `Import-McpProject` / `Write-McpUtf8NoBom` / `New-McpScratchProject`
  `[文件:docs/tasks/PLAYBOOK-group-port.md:137-147]`。
- **相关已声明的收尾事实**：`.ps1` 写工程文件一律走 `[IO.File]::WriteAllBytes` + `UTF8Encoding($false)`
  （Windows PowerShell 5.1 的 `Set-Content -Encoding UTF8` **会写 BOM**；`accept_m1.ps1`、
  `check_contract_subset.ps1`、`mcp014_m3_evidence.ps1` 三处曾正是如此）
  `[文件:docs/tasks/PLAYBOOK-group-port.md:129-136]`。

### (i) `.godot` 内生成的 `.cs` **会被列出**（= (g) 的同一条事实，在 mono 工程上的具体表现）

- 与 (g) 是**同一个机制、同一条锚点**，单列出来是因为写 C# 工程的人最容易先撞到它：真实 mono 工程里
  `res://.godot/mono/temp/obj/**` 下的生成 `.cs` 会出现在 `project_list_scripts` 的答案里，调用方若要只看
  手写脚本请**自行过滤这些路径**（契约描述已写明这一点）
  `[报告:REPORT-067 §1.4]`、`[报告:REPORT-068 §2.2]`、`[契约:701539829ed8]`。
- 一边界的**互补事实**：`.cs` 在 **plain** 构建上**不会**被列出（`ScriptServer` 里没有 `"cs"` 语言），
  这不是缺陷而是「构建有什么语言就列什么」的直接后果，与 `language_unavailable` 口径一致
  `[报告:REPORT-067 §1.2]`。

### (j) **双精度未被默认门覆盖**（除非启用变体）

- 默认门③（以及 ①②④⑤⑥）**全是单精度/脚本级门**：没有任何默认门会构建或运行
  `bin\godot.windows.editor.double.x86_64.console.exe`。本机手工构建 + 手工跑得到的是 **345/345**，
  它是**证据**，不是门的一部分 `[报告:REPORT-071 §B.4]`。
- TASK-073 A 把它变成**显式可选变体**：只有 `-PrecisionVariant double` / `-WithDouble` 才构建并运行；
  **不给开关时默认步表逐条不变、默认时长不增、双精度产物零触碰**（机器证明见 §2.1 门③′ 与 §4）
  `[sha:9c12c2383]` `[报告:REPORT-073 §2,§3.1,§3.3]`。
- **变体本身也是 opt-in 的驱动器级开关**：`mcp057_gates.ps1`（另一个门运行器）**未加**该开关，
  任何不传开关的批次**仍然没有双精度覆盖** `[报告:REPORT-073 §8.2.1]`。
- **为什么不做成默认**：冷构建约 **15 min**，直接违背「默认不增加时长」；若要定期覆盖，建议做成独立 CI 步骤
  或每周一次 `[报告:REPORT-073 §8.4.4]`。
- **相关的设计约束（D-15）**：`Color` 分量与 `PackedFloat32Array` 元素用 `ValueSlot::FLOAT32`（**恒按 32 位判**），
  而不是 `REAL_T`——后者在 `precision=double` 下会放行 `1e300`，让同一缺陷在双精度构建里**复活**。因此
  「收窄必须被拒」这条命题在**两种构建下都存在**（`FLOAT32` 那一半无条件编译）
  `[文件:docs/DESIGN-DETAIL.md:692-705]`、`[报告:REPORT-071 §B.2]`。
- **F-1 的已知边界**：双精度与单精度的**断言数不同**（23 956 vs 23 971）不是删断言，而是
  `if (sizeof(real_t) == 4)` 两条分支的**固有**差异；**用例数两边都是 345**
  `[报告:REPORT-071 §B.3]`、`[报告:REPORT-073 §4.2]`。

### 3.11 其它已声明边界（一并列出，避免漏项）

| 边界 | 内容 | 锚点 |
|---|---|---|
| 锚点判据是**拼写可见的有界保证** | 它只看得见 `git diff` 给出的**路径**：一个「改了但 diff 认为无关」的编译输入、一个 `.json` 驱动的代码生成、`config.py` 之外的 `.py` 生成器都在集合外 | `[报告:REPORT-072 §11.2.1]` |
| `UNCLASSIFIED` 一律红是**保守选择** | 会拒绝一些其实无害的新后缀（代价 = 可能的新假红，收益 = **不可能的新假绿**）；加白名单必须附论证 | `[报告:REPORT-072 §11.2.2]` |
| `ANCHOR_STRUCTURAL_EQUIVALENT` 是**推断**不是验证 | 它说的是「这些提交**不可能**改变编译结果」，不是「二进制里就是这些源码」；所以证据行永远打印锚点 + 完整差异清单，**不**把结论压缩成「等于 HEAD」 | `[报告:REPORT-072 §11.2.3]`、`[报告:REPORT-072 §1]` |
| 变体的串行保证是「**预检 + 纪律**」 | 它构建前检查存活 scons 并拒绝（多进程存活即 exit 4，`-AllowConcurrentBuild` 才可越过）；理论上仍有竞态，D62 仍是**人的纪律**，机器只把它变得**可失败** | `[报告:REPORT-073 §8.2.4]` |
| 红相位脚本会**临时改写一个受版本控制的编译输入** | `mcp073_gate3_double_red_phase.ps1` 有前置条件（文件必须与 HEAD 逐字节一致）、`try/finally` 还原、还原后 sha256/blob/porcelain 三重校验；**但**若进程被硬杀，树可能停在 pre-F-1 版本 —— 这是该脚本唯一残留风险 | `[报告:REPORT-073 §8.2.5]` |
| `-ExpectCases` 判据是 `>=` 而不是 `==` | 允许后续批次**增加**用例、不允许**减少**（与「只允许增加」一致），实际数字每次都打印并落盘 | `[报告:REPORT-073 §8.1.5]` |
| 已知小疙瘩（变体日志落点） | 电池日志目录与变体自己的戳目录是**两个路径**（都会打印）；原因与「为什么不顺手改」已记录 | `[报告:REPORT-073 §8.1.3]` |
| `check_hardcoded_counts.py` 的 2 行 UNCLASSIFIED | 既有小债务（`scripts/mcp071_gate2_live_evidence.ps1:192,266` 的 `176`），该脚本不在任何电池里 | `[报告:REPORT-073 §8.1.7]` |
| `editor_node.cpp:1085` 的分支带 `!cmdline_mode` 守卫 | `--headless`/`--import` **到不了**它——这也是该缺陷长期没被看见的原因；窗口化实测证据见 REPORT-070 §2 | `[报告:REPORT-070-audit-unconfirmed-closure.md §2]` |
| 历史报告的 sha256 会**过期** | TASK-072 把 15 个脚本的锚点断言统一到唯一判据后，这些脚本在**历史报告**里记录过的 sha256 因此变旧（判据语义只在「锚点 vs HEAD」处变宽、`mcp016` 反而变严） | `[报告:REPORT-072 §11.1.1]` |
| `restored=57` vs `REPORT-070` 的 56 | 同一机制，多 1 条被步骤重写的已跟踪证据文件，不是行为变化 | `[报告:REPORT-071 §C.3]` |

---

## 4. 复现步骤（从零到跑通六道门的最小集）

> **前置**：Windows + 该机器已装好的工具链（SCons 4.11.1 / Python 3.9.7 / MSVC 14.42.34433 /
> WinSDK 10.0.26100.0）`[文件:docs/ACCEPTANCE.md:45]`。
> **三条不可协商的约束**：**构建严格串行**（任何时刻只有一个 scons，D62）；**只用 9888/9889，
> 绝不碰 9877**；**不 push**。

```bat
:: 0) 一律从 cmd 打开，进入仓库根（PowerShell 5.1 对中文/编码不友好）
cd /d F:\RustProjects\godot-mcp-pro\code\godot
git rev-parse --short=9 HEAD

:: 1) 串行构建 plain（tests=yes 必需）。绝不要用仓库根的 build-m0.cmd（它不传 tests=yes）
modules\mcp_server\scripts\build_local.cmd -Force

:: 2) 构建锚点（唯一判据；exit 0 = 可用，非 0 = 先重建再跑门）
bin\godot.windows.editor.x86_64.console.exe --version
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\check_engine_anchor.ps1 ^
    -VersionText "<上一步打印的自报串>" -HeadSha <git rev-parse 的结果>

:: 3) 门①（会自己起编辑器 9888 / 游戏 9889，并断言 9877 未被请求）
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\check_contract_subset.ps1

:: 4) 门②（三类证据 + 跨工具活链；响应一律 curl.exe -s -o 落盘）
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp071_gate2_live_evidence.ps1

:: 5) 门③ / 门④（不建端口）
bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="[MCPServer]*"
bin\godot.windows.editor.x86_64.console.exe --headless --test

:: 6) 门⑤（内部含 accept_m1 连跑两次 + 15 步回归电池；会先快照、跑完按声明还原被跟踪证据）
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp056_regression_battery.ps1

:: 7) 门⑥ 三段式（第三段会临时改源码、跑完逐字节还原）
python modules\mcp_server\scripts\check_narrowing_points.py
python modules\mcp_server\scripts\check_narrowing_points.py --coverage
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp031_gate6_coverage_probes.ps1

:: 8) 三个契约机器检查（必须都 exit 0，且断言条数 176 不变）
python modules\mcp_server\docs\scripts\check_tool_groups.py --check-completeness
python modules\mcp_server\docs\scripts\check_tool_groups.py --added
python modules\mcp_server\docs\scripts\check_tool_groups.py --generator-version

:: 9) 六条纪律各自跑一遍（都可独立运行，输出即证据）
python modules\mcp_server\scripts\check_tautologies.py
python modules\mcp_server\scripts\check_tautologies.py --probes
python modules\mcp_server\scripts\check_exit_propagation.py
python modules\mcp_server\scripts\check_exit_propagation.py --probes

:: 10)（可选）一次跑完 22 步并集电池：等于上面的门①③④⑥ + 生成器 + T-059 几步
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp059_gates.ps1

:: 11)（可选）门③ 的双精度变体：先串行构建 .double.（冷构建约 15 min），再跑同一用例集
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp059_gates.ps1 -PrecisionVariant double

:: 12)（需要 C# 成功腿时）串行构建 mono + 程序集；跑完切回 plain
modules\mcp_server\scripts\mcp057_build_mono.cmd
python modules\mono\build_scripts\build_assemblies.py --godot-output-dir=bin --godot-platform=windows
modules\mcp_server\scripts\build_local.cmd -Force
```

**本文作者在 `[sha:b6fbb917b]` 上实跑过的只读检查（可直接复算的数字）**：

| 命令 | 结果 |
|---|---|
| `python modules\mcp_server\scripts\check_tautologies.py` | `TAUTOLOGY CHECK PASS`，exit **0**；`DECLARED SPELLINGS : 9 powershell + 5 python`；`PINNED: 1` |
| `python modules\mcp_server\scripts\check_tautologies.py --probes` | `PROBES: 18/18`，exit **0** |
| `python modules\mcp_server\scripts\check_exit_propagation.py` | `EXIT-CODE PROPAGATION CHECK PASS`，exit **0**；`DECLARED SHAPES : 2 powershell + 1 python`、`DECLARED GUARDS : 10 powershell + 6 python`、`PINNED: 2` |
| `python modules\mcp_server\scripts\check_exit_propagation.py --probes` | `PROBES: 10/10`，exit **0** |
| `python modules\mcp_server\scripts\check_narrowing_points.py` | `scanned=75 pinned=75`（16 个文件），exit **0**；18 条**行号漂移**提示是既有现象、**不是失败** |
| `python modules\mcp_server\scripts\check_narrowing_points.py --coverage` | 打印 **17 种已声明拼写**，exit **0**（`PLAYBOOK §3` 里写的「16 种」是陈旧数字） |
| `python modules\mcp_server\docs\scripts\check_tool_groups.py --check-completeness` | PASS，exit **0**；`176 = 66 + 105 + 5`、`171 + 5 = …`、两个下架名缺失、`BYTES ADDED 8072` |
| `python modules\mcp_server\docs\scripts\check_tool_groups.py --added` | PASS，exit **0**；5 个新增工具、`SHA256 0295cf86…` |
| `python modules\mcp_server\docs\scripts\check_tool_groups.py --generator-version` | PASS，exit **0**；三方一致 `1.20.0` |
| 三个二进制的 `check_engine_anchor.ps1` | plain `ff796dbf9`、mono `ff796dbf9`、double `9c12c2383` 对 HEAD `b6fbb917b` **全部** `ANCHOR_STRUCTURAL_EQUIVALENT` + `RESULT PASS`（exit 0）；红计数 0 |

> **不要**在没有重建的情况下相信门的结果（R-1）；**不要**为了「跑得快」并发两个 scons（D62）；
> **不要**在任何脚本里请求 9877。

---

## 5. 仍未做 / 已明确否决的项（各有理由，不要重复争论）

### 5.1 引擎/写出口层面

| 项 | 状态与理由 | 锚点 |
|---|---|---|
| **D-7：`save_custom_section` 用「删原文件 + rename」而不是 POSIX 原子替换** | **有意保留**（极小窗口；已有备份 + 失败回滚 + 并发不撕裂证据）。要低成本改需动 `core/io` 或 `MoveFileEx(MOVEFILE_REPLACE_EXISTING)`，超出授权面 | `[报告:REPORT-059-section-publish-switch.md §4.2,§6.6]` |
| **`editor_reload_plugin` 的「按节化」** | **未做**。该工具的全部工作就是**删键**（`settings->clear(key)`），而新 API 的语义是「按名字替换值」、从不删键；改成按节写需要从内存重建整个 `[autoload]` 节并重排其余节 → 是一次真实且高风险的**行为变更**，不划算。它保留整文件重写，并在契约描述里**诚实说明** | `[报告:REPORT-059-section-publish-switch.md §6.5]`、`[文件:docs/DESIGN-DETAIL.md:322-328]` |
| **`project.godot` 文本「拼接发布」器** | **已否决（本批不实现）**。spike 证明**技术可行**（真游戏进程读到、注释保留、幂等），但有 **R1–R9 九条风险**，其中 **R1 已复现为静默失败**（`[input]` 非末节时新键落错节 → 游戏读不到）；且拼接器直接改原文件会与既有「临时兄弟文件 + rename」的原子写产生**两种并发语义**。只有「保留手写注释」被确认为**硬需求**时才立项 | `[报告:REPORT-AUDIT-RACING-BACKLOG.md §6.2,§6.3]`、`[报告:REPORT-057-mono-anchor-and-settings-publish.md §4]` |

### 5.2 试测（racing/breakout）裁决里**明确不建议做**的 9 项

来源：`RACING-FINDINGS.md` §3.2 的九行表（决策日志 D98 记「4 条建议合并 + **3 条明确不建议**」，
独立确认轮的 §7.3 亦维持）`[报告:RACING-FINDINGS.md:199-211]`、`[报告:REPORT-AUDIT-RACING-BACKLOG.md §7.3]`：

1. **把 `editor_open_scene → editor_get_scene_tree → editor_add_nodes_batch` 合成一个工具** —— 三步并一后
   失败时**无法定位**是哪一步（§A C2 的硬要求）；而且 `editor_add_nodes_batch` 本身才是问题所在，修它更值
   `[报告:RACING-FINDINGS.md:203]`。
2. **合并 `editor_list_signal_connections` 与 `editor_analyze_signal_flow`** —— 两者语义**故意不同**
   （前者含全部连接、后者只收 `CONNECT_PERSIST`），契约两侧 `description` 都明写并互相指路；合并会同时毁掉
   两种能力 `[报告:RACING-FINDINGS.md:204]`。
3. **改 `editor_get_scene_tree` 的 `max_depth` 默认值** —— 契约里默认**已经是 `-1`（无限）**，调用方是**显式**
   传 6/8/12 的；这条建议的原归因**已撤回** `[报告:RACING-FINDINGS.md:205]`。
4. **把 `editor_save_scene` 改成「保存并返回文件全文」** —— 会把大响应塞进保存路径（场景 `rb` 已达 6556 B
   且会继续增长）；`{verify:true → sha256+bytes}` 更小、更可判定 `[报告:RACING-FINDINGS.md:206]`。
5. **为 AN-8 去改 `mcp_trace.cpp` 的打开语义（改成每次截断/轮转）** —— 成因已定位为**测试脚本自己
   `Remove-Item`**；模块的**追加**语义恰恰是观察者能 tail 文件的前提；只加一行 `trace_opened` 记录即可
   `[报告:RACING-FINDINGS.md:207]`、`[报告:RACING-OBSERVATIONS.md OBS-005/OBS-023]`。
6. **单端改 `running_game_get_node_properties` 的 `null` 语义（AN-2）** —— 源码明文声明是有意行为且已成调用方
   契约；单端改成硬拒绝会**破坏既有调用方**；「两端统一成哪一侧」属**决策层议题**
   `[报告:RACING-FINDINGS.md:208]`。
7. **现在去改 `editor_analyze_screenshot_diff` 的绝对路径支持** —— 契约写的是「路径或 base64」，`user://` 与
   base64 都能用；绝对 Windows 路径被拒只是**限制**，没有任何工作流因此阻塞 `[报告:RACING-FINDINGS.md:209]`。
8. **把 `source_path`/`target_path` 全面重命名成 `node_path`** —— 会动契约 sha 与 171 条逐字门，收益只是手感；
   **只做 description 级指路**（TASK-051 已做）`[报告:RACING-FINDINGS.md:210]`。
9. **为 `editor_setup_collision_shape` 改行为（自动挂到物理体）** —— 现行为**诚实**（回
   `collision_node_path`）；改名/改行为都会破坏既有调用方，只改一句描述 `[报告:RACING-FINDINGS.md:211]`。

### 5.3 试测裁决里**明确不做**的单数/复数形状统一

| 项 | 状态与理由 | 锚点 |
|---|---|---|
| **F-066-3：单数 `project_validate_script` 与复数 `project_validate_scripts` 形状不同** | **不修（口径已由契约写明）**。单数对「没被任何东西编译过」的文件回 `-32000`（message 明说 `not compiled`，**绝不**回 `valid:false`），复数回 `results[].category` 结果体——**这是两个已声明契约的有意不同读法**，不是文档缺口。要「统一」只能改行为 = 破坏性变更，而 176 条契约对单数的输入/结果面**没有**授权；加增量字段又会**制造**契约没写的行为。若决策者要统一，**另立任务** | `[报告:REPORT-067-script-listing-and-editor-save.md:190]` |

### 5.4 已登记但**未做**的收尾项（建议单开小批次）

- **`project_list_scripts` 的 `.godot` 收窄**：只声明、不收窄（理由见 §3(g)）；若要做，建议给
  `_collect_scripts_recursive` 加一条「跳过 `ProjectSettings::get_project_data_dir_name()`」+ 一条 doctest
  （断言 `.godot` 不入、`.hiddendir` 仍入），**不要**改成「跳过所有 `.` 前缀目录」
  `[报告:REPORT-067 §5.1]`、`[报告:REPORT-068 §6.3]`。
- **三类 PINNED（会随契约增长过期）**：`scripts/mcp063_product_defects_evidence.ps1:374,468,482`（176/72/153）
  与 `scripts/mcp066b_run.ps1:349,730`（153/72）——下一批**增加工具/实现组**时一并改为派生
  `[报告:REPORT-068 §6.1]`。
- **`check_hardcoded_counts.py` 的 2 行 UNCLASSIFIED**（§3.11 末）`[报告:REPORT-073 §8.1.7]`。
- **mono 的 `engines_match_head` 漂移**曾让回归电池整脚本 `exit 1`（`FAILED STEPS: 2`），归因是
  TASK-070 提交留下的漂移、**不是**当时那一批引入的；修法是重建 mono 再重跑那两步
  `[报告:REPORT-071 §C.3,§D.4.2]`。
- **`DESIGN-DETAIL` 的门③ 口径与（可选）GDR-29**：**决策者落笔**，实现者不改；建议文本已在报告里
  `[报告:REPORT-073 §6]`。
- **`mcp057_gates.ps1` 是否也接双精度开关**：本批按任务书只在 `mcp059_gates.ps1` 落点；两个都通是 3 行改动 + 一次重跑
  `[报告:REPORT-073 §8.4.3]`。

---

## 6. 自检（本文每一条断言如何被验证）

**自检判据**：本文**没有**无锚点的结论。每条断言落在三类可核对形态之一：

| 类别 | 读者怎么核 | 本文中的例子 |
|---|---|---|
| **A. 可机器复算** | 按 §4 的命令跑，或按 §4 末尾那张表直接对照数字 | 契约 176 / `171+5=66+105+5` / `scanned=75 pinned=75` / `PROBES 18/18`、`10/10` / `generator 1.20.0` / 三个二进制的 `ANCHOR_STRUCTURAL_EQUIVALENT` / `BYTES ADDED 8072` `SHA256 0295cf86…` |
| **B. 可按 `文件:行` 核对** | 打开对应源码行；或按契约 sha 读 `tools_list.renamed.json` 的字段 | 三个引擎补丁的全部落点（§1.3）/ HTTP/JSON-RPC 规范行（§1.4）/ 三类脚本判决的落点（§3(f)）/ 门与守卫的挂载点（§2.2） |
| **C. 可按证据路径核对** | 打开 `docs/reports/evidence/<task>/…` 或对应 REPORT 的章节 | `EV72/counterexample_probe.txt`、`EV72/judge_probe.txt`、`EV73/anchor_stale_compiled_probe.txt`、`EV73/gate3_double_summary.txt`、`EV73/battery_default_summary.txt`、`EV61/s1-marker`…`s5-old-protocol`、`EV71/probe_mcp071.txt` |

**本次交付的纪律核对（我在 `[sha:b6fbb917b]` 上做的，只读）**：

| 要求 | 状态 |
|---|---|
| **不修改任何代码 / 脚本 / 契约** | ✅ 本文写作过程中**没有**编辑任何 `.cpp/.h/.json/.ps1/.py/.cmd`；只**新增/追加** `docs/**` 下的两份文档（本文 + `REPORT-073` 的 B 部分） |
| 契约 176 条数不变 | ✅ 现场 `--check-completeness`：`176 = 66 + 105 + 5`，`177` 不出现；契约文件 sha `70153982…` 与 `REPORT-068` 记录一致 |
| **绝不占用/杀/重启 9877** | ✅ 本次全部命令都是**只读**（python 检查器、`--version`、锚点判据、`git`、文件哈希）；**没有启动任何引擎进程**，因此没有占用 9888/9889，更没有碰 9877 |
| 构建严格串行 | ✅ 本次**没有运行任何 scons**（未构建） |
| 禁止 push | ✅ 未 push |
| `.ps1` 纯 ASCII | ✅ 未新增或修改任何 `.ps1` |
| 红相位输出当场保存 | ✅ 本批的 B 部分本身不产生红相位；所引用的红相位证据（`EV73/gate3_double_red_phase_RED.txt`、`EV71/doctest_module_double_RED.txt`、`EV73/anchor_stale_compiled_probe.txt`）均为**已落盘的原始输出** |
| 结论按 D86 标锚点 | ✅ 全文结论都带 `[sha:…]` / `[契约:…]` / `[文件:行]` / `[报告:… §x]` / `[EV…]` |
| 产物绝对路径 | ✅ §0、§2.2、§4、§6 的路径均为绝对路径或从仓库根可解析的相对路径（`modules/mcp_server/...`），并给 `docs/reports/evidence/` 的固定前缀 |

**本文章节完整性**（对照 TASK-073 §B 的六项要求）：

| 要求 | 本文位置 |
|---|---|
| ① 交付物清单（176 = 171 + 5 / 三个引擎补丁 / HTTP-JSON-RPC 契约 / mono 与非 mono / 端口规则） | §1（§1.1–§1.5） |
| ② 门与纪律（六道门 + 门完整性六条纪律，每条一句话说明防什么 + 反例演示脚本路径） | §2（§2.1–§2.3） |
| ③ 已知边界与已声明限制（(a)..(j) **完整**） | §3（(a)–(j) + §3.11 补充） |
| ④ 复现步骤（从零到跑通六道门，含从 cmd 启动、串行约束、端口约束的最小集） | §4 |
| ⑤ 仍未做/被否决项（D-7 原子替换、`editor_reload_plugin` 节级化、`project.godot` 拼接器、9 条不建议项等，各一句理由） | §5（§5.1–§5.4） |
| ⑥ 自检（每条断言可验证 / 不得有无锚点结论） | §6（本节） |
