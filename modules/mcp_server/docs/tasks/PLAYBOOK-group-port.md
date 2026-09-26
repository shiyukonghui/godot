# PLAYBOOK — B1..B5 单组工具移植（可复用任务书规范）

> 本手册是**每一组工具移植任务的共同规范**。每组的任务书只需给出：组名、成员清单、组特有注意事项、报告路径，
> 并声明「按本手册执行」。执行者必须**完整阅读本手册**，它自包含。

## 0. 上下文

用户裁决：**优先完成 Godot 内置 MCP 模块的工具集成与测试；harness（hof-rs）暂停**
（`F:\moonbit-hof-rs\DECISIONS.md` 的 D43）。

> **关于决策日志（避免误解，已发生一次）**：决策日志**在 harness 仓库**
> `F:\moonbit-hof-rs\DECISIONS.md`（对本模块的执行者**只读**）。
> **本 fork 内没有也不得新建** `DECISIONS.md` 或 `docs/spec/**` 之类的**竞争性规范/日志文档**——
> 已发生过两次（`docs/spec/TASK-005/`、`docs/spec/TASK-016/`），均已删除。
> 执行者只写**报告**（路径由任务书指定）；认为规范有误或缺失，**在报告里报缺陷**。
模块位于 `code\godot\modules\mcp_server\`，把 MCP 工具逻辑内置进引擎本体（编辑器与游戏两个进程各一份实现）。
命名与处置的唯一事实源是 `docs/tool-rename-map.json`（v1.1，未再改动）；
**期望契约**是 `docs/tools_list.renamed.json`（171 条，`_meta.order_normative=false`）；
**组清单**是 `docs/tool-groups.json`。

## 1. 必读（只读）

| 文件 | 作用 |
|---|---|
| `docs/DESIGN-DETAIL.md` | §10 批次、§16 执行顺序、**§17/GDR-19 框架**（注册分组、ToolBuilder、错误语义、编辑器守卫、串行纪律）、§5–§6 传输/JSON-RPC 契约、GDR-16/17/18 |
| `docs/tools_list.renamed.json` | 该组工具的 `description` 与 `inputSchema` **唯一权威**（逐字相等） |
| `docs/tool-groups.json` | 组清单与「41 个恰好各一次」的不变式 |
| **引擎源码（第一参考源）** | `core/**`、`scene/**`、`editor/**`（本 fork 内，**只读**）——**「怎么用才顺手」「参数该长什么样」「返回什么才可链式喂回」的唯一权威** |
| 迁移源（**仅类别参考**） | `godot_mcp_gdext/src/commands/*.rs`、`addons/godot_mcp_rs/**`（**只读**）——**只用来确认「有哪些类别的工具、大致干什么」**，**不是行为预言机** |
| `docs/scripts/check_tool_groups.py` | 组清单机器校验（可选自跑） |
| 已完成组的报告/代码 | `tools/project_read_template.{h,cpp}`（**照它的写法**）、`docs/reports/REPORT-002-b1-framework.md` |

## 2. 单组工作流（8 步）

1. **读契约**：把该组每个工具在 `tools_list.renamed.json` 中的 `name`/`description`/`inputSchema` **原样抄进脑子**——
   这是逐字门的对象；**不要自行改写描述或 schema**。
2. **以引擎源码为准设计「顺手的调用形态」，再读迁移源只用来确认类别与用途**：
   - **先读引擎**：这个能力在引擎里是哪个 API？它**一次调用能做到什么**？返回值里哪些字段是**可链式喂回**的？
     参数用引擎自然的形态（节点路径/资源路径/`Variant` 结构）时**调用方要写多少**？
   - **再读迁移源**：只为确认「这类工具确实存在、它的用途是什么」，**不要**把它当成参数表与返回形状的权威；
   - **写出该工具的自然契约**：参数名/类型/必填性、返回字段与形状、上限/截断、大小写/单位、错误情形，
     并**明确说明每一处为什么这样设计**（依据引擎的哪个 API）。
   - **与迁移源不同是常态，不是例外**：只要引擎支持更顺手的形态，就按引擎来，并在报告里记录差异与理由。
3. **实现**：新建/扩展 `tools/<group>.{h,cpp}`，每个工具**必须**经 `MCPTools::ToolBuilder` 注册
   （`register_tool` 已私有化，绕过会让构建失败）；显式声明 `channel`/`verb`/`scope`/`mutating`；
   参数用 `require_*`/`optional_*`；成功走 `MCPTools::content_result(...)`；
   错误走 `MCPToolError`（`-32602` / `-32001`（带 `data.suggestion`）/ `-32000` / `-32603`）。
   编辑器专有 API 用 `MCP_EDITOR_TOOLS_ENABLED` 守卫（本 fork 的定义在 `tools/tool_builder.h`）。
4. **注册**：在 `tools/registration.cpp` 的 `register_all_tools()` 中**追加该组的 include + 一行调用**
   （**一批只有一个实现者在改树**，见 §17.1；不得改别组文件）。
5. **测试（TDD 优先）**：为每个工具加 doctest，覆盖：成功路径、缺参 → `-32602`、
   底层失败（资源/节点不存在 → `-32001` 或明确的工具错误）、以及该工具特有的边界（上限、大小写、空结果等）。
   **先写会失败的测试再实现**；红/绿两阶段的真实输出都要进报告。
6. **跑四道门**（见 §3）。
7. **提交**：英文提交信息，一条提交对应一组（可拆「实现」+「测试」两条）；**禁止 push**。
8. **写报告**：路径由该组任务书指定；格式见 §4。

## 3. 四道门（缺一不可，全部自己跑并贴真实输出与退出码）

| 门 | 命令 | 通过标准 |
|---|---|---|
| ① 契约子集逐字 | `scripts\check_contract_subset.ps1 -Group <组名>` | **实况 `tools/list` 必须等于 `tool-groups.json` 中所有 `implemented=true` 组的并集**（因此该脚本按**并集**断言，而不是单个组）；其中本组工具在**编辑器 9888 与游戏 9889** 上各条 `name`/`description`/`inputSchema` **逐字 True**；任何「未实现却已注册」的工具都会导致失败 |
| ② 三类证据 | `curl.exe --data-binary @file` 打 9888（必要时 9889） | 每个工具：成功 / 缺参 / 底层失败 各一组真实请求与响应；**哪一类不可构造必须显式声明原因**。**并且**：每组还要给出一条**跨工具的端到端活证据链**（多个工具按顺序调用、观察状态变化）——这条比单工具证据更容易抓到真缺陷（已实证：属性过滤器静默丢脚本变量，doctest 抓不到、活证据链抓到了） |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | 全绿（基线见上一份报告，只允许增加）。**门③ 默认是单精度门**：它跑的是 `bin\godot.windows.editor.x86_64.console.exe`，即 `precision` 缺省（`float`）。**`precision=double` 是门③ 的可选变体**（TASK-073 A）：只有**显式开关**才构建并运行 —— `scripts\mcp059_gates.ps1 -PrecisionVariant double`（等价 `-WithDouble`）会在默认步表之后**追加一步** `gate3_double_variant`（`scripts\mcp073_gate3_double.ps1`：串行复用 `scripts\mcp070_build_double.cmd` 构建 → 用 `scripts\check_engine_anchor.ps1` 判锚点，`ANCHOR_EQUAL`/`ANCHOR_STRUCTURAL_EQUIVALENT` 通过而 `ANCHOR_STALE_COMPILED` 必须红 → 在 `.double.` 二进制上跑**同一个** `[MCPServer]*` 用例集并要求全绿）。**不给开关时步数、结果与默认时长逐项不变、不构建**；因此**双精度仍然没有被默认门覆盖**。红相位重放见 `scripts\mcp073_gate3_double_red_phase.ps1`，全部证据见 `docs\reports\REPORT-073-double-gate-and-handover.md` |
| ④ 全引擎回归 | `--headless --test` | **0 failed**；passed 只允许因新增测试增加 |
| ⑤（每批收口） | `scripts\accept_m1.ps1` **连跑两次** | 全过，两次 PASS 清单一致 |
| ⑥ 收窄点清单（**每批必跑**，GDR-24） | `python scripts\check_narrowing_points.py`，**另加** `python scripts\check_narrowing_points.py --coverage` 与 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp031_gate6_coverage_probes.ps1` | **exit 0**：`tools/**` 里落在**脚本已声明**的拼写集合内的每个收窄点，都带 `// MCP-NARROWING: <ID>` 且在脚本 `PINNED` 清单里登记了理由（`gated`/`pregated`/`safe`/`gate` 四类之一）。**新增未标注的收窄点 = 门失败**；清单条目与源码失配（标记消失/改名）同样失败。**保证以「已声明集合」为界**：`--coverage` 打印该集合与**不在**集合内的部分，集合内**每一种**拼写都有「插入即 exit 1」探针（`mcp031_gate6_coverage_probes.ps1`，TASK-031 起 77/77）；当前树必须 `scanned == pinned` 且 0 误报 |

> **门⑥（TASK-023 新增，GDR-24）为什么是独立一道门**：同一类「静默写错值」已出现**四种形态 + 一种构建配置形态**，
> 每次都是「按形状补丁」、每次都漏下一个形状。根因是闸门挂在 `coerce_to_property_type` 内部，
> 只覆盖走 `Object::set()` 的属性写；任何「先算值、再调专用 setter」的路径（视口相机 `position`/`rotation_degrees`/`fov`、
> 环境 `bg_color`/`ambient_color`、注入输入事件的坐标与 `strength`、场景回放的向量）都会绕过它。
> 门⑥ 把这些点**清单化 + 机器校验**：想新增一个收窄点，就必须在源码标注并说明它经过哪次闸门，
> 否则 CI 级检查直接失败（也见 `docs/DESIGN-DETAIL.md` §22 GDR-24）。
> **`Color` 分量与 `PackedFloat32Array` 元素用 `ValueSlot::FLOAT32`（恒按 32 位判）而不是 `REAL_T`** ——
> 后者在 `precision=double` 构建下会放行 `1e300`，让同一缺陷在双精度构建里复活（D-15）。

> **⚠️ 门⑥ 的保证是「有限集合」的（TASK-031 修订，**取代**旧的无边界说法）**：第一版扫描器只认六种**字面拼写**
> （`(real_t)`/`(float)`/`Color(`/`Vector2(`/`Vector3(`/`Vector4(`），M4d 第四次独立验收用五个探针实测
> **全部都能绕过**（仍 exit 0）：`const real_t x = 1.0e300;`、`static_cast<float>(1e300)`、`::Color(1e300,0,0,1)`、
> `Vector3{1e300,0,0}`、`Color` 与 `(` 跨行。**因此不得再把门⑥ 描述成「每个收窄点都必须标注」**（§22.3b）。
> TASK-031 之后扫描器覆盖 **16 种已声明拼写**（`--coverage` 打印）：C 风格/`static_cast`/函数式转换、
> `::` 限定、`T(...)`/`T{...}`/`T name{...}`/`T name = {...}`、跨行构造，以及「字面量装不进 32 位 float」的
> 隐式初始化与构造参数形态；集合内**每一种**拼写都有「插入即 exit 1」探针
> （`scripts\mcp031_gate6_coverage_probes.ps1`，77/77；当前树 `scanned=30 pinned=30`、0 误报、探针后字节还原）。
> **但它仍然只看得见「拼写可见」的收窄**：运行时把 `double` 隐式写进 `real_t`/`float`（`real_t x = some_double;`）、
> 整数收窄（`(int)`/`Vector2i`/packed int）、集合外拼写都在门⑥ 之外，必须靠代码审查与行为证据。
> **编译器级检查（MSVC `/we4244`、GCC/Clang `-Wfloat-conversion`）经实测不可用**：它无法只作用于 `modules/mcp_server/**`
> ——本模块的翻译单元会包含引擎头（`core/math/*.h`、`core/string/ustring.h`、`core/typedefs.h` 等），
> 这些头本身就大量触发 C4244，而 `SConstruct` 全局 `/wd4244` 的注释正是「Unavoidable at this scale」；
> 把告警升级为错误会让构建在**不许修改的引擎代码**上失败（实测见 `docs/reports/REPORT-031-gate6-coverage.md` §2）。
> → 门⑥ 是**三道腿之一**（机器检查 + 代码审查 + 行为证据），**不是**唯一证据；任何新增/修改收窄代码的批次
> **必须**在报告里逐条列出「新增点 × 它经过的闸门 × 证据」（§22.3b 规则 2/4），不得只贴门⑥ 变绿。

> **证据采集一律用 `curl.exe --data-binary @file`**：JSON body 作为 Windows 命令行参数会丢引号 → `-32700`。
> **端口纪律**：用户正在使用的 Godot 4.7.1-mono 占用 **9877**（PID 36392）——**绝不占用、绝不杀/重启**；
> 测试用 **9888（编辑器）/9889（游戏）**；scratch 放 `%TEMP%`。
>
> **⚠️ 门必须先绑定构建（M2 验收发现的流程风险 R-1）**：`bin/` 不受版本控制（`.gitignore` 忽略 `[Bb]in/`），
> 门会在**陈旧二进制**上跑出假红（M2 验收开工时二进制落后 HEAD 一个任务，会把 B2 误判为 19/25）。
> 因此**每批开跑门之前**必须：①按 `scripts/build_local.cmd`（`tests=yes`）重建；
> ②校验 `--version` 自报的 hash 前缀 == `git rev-parse --short HEAD`（不一致就先重建）；
> ③改动 `tests/*.h` 后删除陈旧的 `test_mcp_server`/`test_main` 对象再构建。
>
> **⚠️ 门配置：一律用 `modules/mcp_server/scripts/build_local.cmd`（含 `tests=yes`）**
> ——**不要**用仓库根的未跟踪脚本 `build-m0.cmd`（它**不传 `tests=yes`**：`--version` 校验会通过，
> 但 `--test` 会**直接 abort**，M4 验收已踩到）。
>
> **⚠️ 静默错值有两个层级，验收必须分别覆盖（M4 验收 D-1/D-2）**：
> ①**整值级**（`position: 1e20`）已修；②**分量级**（`position: {"x":"abc"}`）与
> ③**字符串级**（`rotation: "abc"`）**仍会静默写默认值并报成功**——`can_convert` 门只作用在
> 「整体转换关系」上，分量与 `STRING→FLOAT/INT` 需**各自的**可解析性/有限性判定。
> 验收证据必须能**区分「拒绝」与「按引擎语义写默认值」**：
> **错误码 + 前后场景 sha256 相同 + 旧值仍为旧值**，*仅*比较「读回值 vs 请求值」**不足以**判定
> （这正是 D67 漏掉该类的原因）。
>
> **⚠️ 禁止并发跑两个 scons**（D62，与 R-1 同类风险）：两个进程会同时重写生成头
> `modules/modules_tests.gen.h`，产生**一批与本批无关的假编译错误**；而且「杀死后台任务」**不保证**
> 其 scons 子进程也停。构建一律串行，且**不要抑制 scons 输出**。
>
> **C# 相关的实测事实（M3 首测 + M3 验收修正，写 C# 工程时会踩）**：
> ①`running_game_execute_gdscript` 编译到的是一个**裸 `RefCounted`**，**没有 `get_node()`** ——
> 要用 `Engine.get_main_loop()` 拿场景树。
> ②**非 `[Export]` 的 `public` 字段不进 `get_property_list()`，但 `Object::get/set` 仍可按名读写它**
> （`csharp_script.cpp:1487-1521`；实测：全量列举 29 键不含 `PlainField`，但按名 `set` 成功 `4242→7`）。
> **B3 的节点写族不要据「不可达」做设计**：属性表用于**校验/类型判定**，但「按名可写」这一事实要作为已知行为处理
> （要么显式允许、要么显式拒绝并在报告说明）。
>
> **⚠️ scratch 工程一律不写 BOM；`--import` 必须校验退出码 + 有界重试 + 可诊断输出**
> （M3 发现，**TASK-028 D-1 修正判据**）：
> ① 写工程文件一律走共享助手 `scripts\mcp_import_guard.ps1` 的 `Write-McpUtf8NoBom` /
> `New-McpScratchProject`（`[IO.File]::WriteAllBytes` + `UTF8Encoding($false)`）。
> Windows PowerShell 5.1 的 `Set-Content -Encoding UTF8` **会写 BOM**——本批之前
> `accept_m1.ps1`、`check_contract_subset.ps1`、`mcp014_m3_evidence.ps1` 三处正是如此。
> ② `--import` 的**退出码必须校验**：它可能以 `0xC0000005`（退出码 `-1073741819`）结束，
> 而工程已被留在**半导入**状态，此后的每一条断言都在错的输入上跑（门仍可能全绿）。
> ③ **必须有界重试**（默认 3 次），且**每次失败**都打印命令、退出码、工程路径、日志路径与日志尾部
> ——共享助手 `Import-McpProject`；`scripts\mcp009..mcp027` 与两个门脚本已全部改为调用它，
> 不再各自维护一份循环。
> ④ **判据修正（TASK-028 实测，覆盖 M3 的旧结论）**：`scripts\mcp028_import_crash_probe.ps1`
> 用 7 个变体 × 6 次全新工程首导（含 `.tscn` / 不含、`.tscn` 带 BOM / 不带、`project.godot` 带 BOM、
> `.tscn` 含 `ext_resource`、`--mcp-port` 缺省 / `=0` / `=9888`）共 **84 次**，**全部 exit 0**，
> `Parse Error` 一次未现 —— 所以「`.tscn` 带 BOM 必崩」「含 `.tscn` 的新工程首次必崩」**都不成立**，
> 旧记载（PLAYBOOK 本节旧文、`docs/reports/REPORT-027`、`mcp016` 的注释）是**间歇性**引擎侧崩溃：
> `0xC0000005` 在本项目历史上出现过 4 次（M3 / mcp016 / mcp026 / mcp027），TASK-028 实测**无法复现**，
> 也**无法归因到本模块**（见 `docs/reports/REPORT-028` 的根因判定与上游材料）。
> 纪律因此不依赖「哪个变体触发它」，而依赖「校验 + 重试 + 诊断」这三件无条件正确的事。

## 4. 报告格式（写到该组任务书指定的路径）

- `status`、`commits`（sha + 一行说明）
- **逐工具表**：`new_name` | 迁移源位置（**仅类别参考**）| **引擎依据**（你用了哪个引擎 API、为什么这是自然形态）|
  **自然契约**（参数/返回形状/上限/大小写/单位/错误）| C++ 落点 | 与迁移源的差异**及理由**（差异是常态）
- 红/绿证据（doctest 红阶段与绿阶段的真实输出）
- 四道门的真实输出与退出码
- ②的三类证据（真实请求与响应片段），以及不可构造类的声明
- 该组脚本/文件的 sha256（若该组动了契约或生成器）
- `deviations`（与手册/任务书的任何偏离，逐条显式列出）、`blockers`、`next_step_recommendation`

**返回给决策者**：≤15 行总结 + 报告路径。

## 5. 硬性约束

- **只允许修改** `code\godot\modules\mcp_server\**`。其它一切（引擎其它目录、`godot_mcp_gdext`、**整个 hof-rs 仓库**）**只读**。
- **不得**注册未实现的工具；**不得**注册 2 个 `unregister_until_implemented` 项；
  `fix_implementation_first` 的工具**必须先写红测试证明当前缺陷，再修实现**
  （当前这类工具集中在 `editor_write_scene_editor` 组：`editor_remove_output_log` 等；
  数据破坏项 `editor_set_tilemap_cell` 族在 B5）。
- **不得**修改契约/映射/文档生成器来完成本组任务——若发现契约有误，**停下来在报告里报缺陷**，不要自行改契约。
- 不得安装依赖；不得访问 100.105.152.101:18080；不得伪造任何输出（之后有**全新子代理**独立验收）。
- 工作树收尾只应剩既有未跟踪物：`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`。

## 6. 已知偏差（各组应沿用，不必重新争论）

> **总纲（决策者指令，D74）**：**迁移源不是完美预言机**。它**只**回答「有哪些类别的工具、大致干什么」；
> **「怎么用才顺手」以引擎源码为第一参考源**（本 fork 的 `core/**`、`scene/**`、`editor/**`）。
> 因此下面这些「偏差」不是例外，而是**正常的设计选择**；反之，**把迁移源的怪癖照抄下来才是要避免的**。

1. `path` 不存在 → `-32001` 带 `data.suggestion`（迁移源是静默空结果）；**接受**。
2. `optional_*` 存在但类型错 → `-32602`（迁移源静默忽略）；**接受**。
3. `normalize_project_path` 折叠 `.`/空/仅空白段（`res://a//b` → `res://a/b`），`..` 在折叠前拒绝；**接受**。
4. `tools/list` **顺序非规范**，但同一次构建内必须**确定性**（含跨进程重启一致）。
5. 映射 `reason` 里的源码引用指向**迁移源**（`godot_mcp_gdext`/`addons`），**不因 C++ 重写而改写**
   （改写会动映射 sha → 文档指纹 → 契约 `_meta.map_sha256`）；**as-built 位置写进本组报告**即可。
6. **迁移源本身有缺陷时，以「工具真的能用」为准并显式记录**（不得为了「与参照逐字一致」而复刻坏行为）。
   已实证四例（新增一例的编号沿用决策层的累计计数）：
   - `project_get_scene_exports`：迁移源用**字面量 1024** 判导出（本 fork 该位是 `PROPERTY_USAGE_NO_INSTANCE_STATE`），
     **恒返回 `count:0`** → C++ 版改读 `Script::get_script_property_list()` 并以 `PROPERTY_USAGE_EDITOR` 判定。
   - `project_analyze_scene_complexity`：编辑场景回退用 `SceneTree::get_edited_scene_root()`（编辑器持续同步的镜像），
     因为 `EditorInterface` 版本**没有 null 检查、在 doctest 进程实测 SIGSEGV**。
   - `editor_analyze_signal_flow`：迁移源写按 `flags & 1` 判「持久连接」，但 **Godot 4 里 `CONNECT_DEFERRED = 1`、
     `CONNECT_PERSIST = 2`** → 照字面实现普通场景**恒返回 `nodes: []`**。
     C++ 版按意图用 `CONNECT_PERSIST`，且**契约描述已用 `DESCRIPTION_OVERRIDES`（`mode=replace`）纠正**
     （TASK-007）。**映射 `reason` 里残留的 `flags & 1` 措辞不再作为行为依据**，以契约为准。
   - `running_game_set_node_property`（**第 7 例**，TASK-014 D-1，M2 验收实测）：对**节点根本不存在的属性**，
     迁移源无条件回 `set: true`（`addons/godot_mcp_rs/mcp_runtime_agent.gd:159-160`）；本实现原先回
     `{"old_value":null,"new_value":null}` 的成功形状，同样是「什么也没发生」被读成「已写入」。
     → C++ 版在写入前**先问对象有没有这个属性**（`get_property_list()`，因为「声明类型是 `Variant::NIL`」与
     「不存在」在 `property_type_of` 里同形），没有则 `-32001` + `data.suggestion`。
     注意：本条**不是与迁移源的行为不一致**，而是「工具真的能用」标准下的诚实性缺口。
   - 共同点：**行为以「工具真的能用」为准，描述以契约（经 override 纠正）为准，映射 reason 仅供参考**；
     分歧必须在报告里显式记录。
7. 路径参数一律**归一后回显**（`res://a/./b` → `res://a/b`），迁移源是原样回显。
8. 迁移源的非确定行为（如 `HashMap` 迭代序、编辑器内部路径里带**每次运行都变的节点 id**）应改为
   **确定、可复现**的形态；**8b（由 D74 修订）**：迁移源的**怪癖不再默认保留** ——
   任何「迁移源这样写、但引擎明明能给更有用结果」的地方，**按引擎来**并在报告里记录理由。
   已列入待办的具体项见 D74 的**顺手性清单**（例如 `get_scene_dependencies` 的 `type` 恒空串、
   `assign_shader_material` 忽略 `material_slot`、`Vector4`/packed 的读回形状是 `String` 而 `Vector2` 是对象）。
9. **文本长度字段的单位**：迁移源（Rust）用的是**字节数**（`String::len()`）。C++ 版若用 `String::length()`
   会得到**字符数**，属于不必要的偏离 → **除契约明确写了字符数，一律返回 UTF-8 字节数**。
10. **顺手性（ergonomics）是验收条款**（D74）：工具必须让调用方**一趟做完引擎一趟能做的事**、
    参数取**引擎自然形态**、返回字段**可链式喂回**（写出对象就能被别的工具直接读）。
    若一个工具要求调用方做「多步舞蹈」才能拿到引擎一次调用就能给的结果，**算缺陷**（minor 起），
    在报告里给出「引擎本来能做到什么」的证据。

## 7. 纪律补强（源自已发生的两起真实事故）

1. **证据采集禁止用 `Out-File` / 管道承载响应体**：已发生过一版 `tools/list` 证据经 `Out-File -Encoding ascii`
   管道被污染（每个非 ASCII 字符塌成 `?`，字节数被记为错值），导致独立验收判 `fail`。
   → 响应体一律 `curl.exe -s -o <file>` 落盘，或用 `[IO.File]::WriteAllBytes(...)`；比较前先算 sha256。
2. **实现者不得创建竞争性规范文档**：不要把 `REQUIREMENTS.md` / `DESIGN-OVERVIEW.md` / `DESIGN-DETAIL.md`
   写进仓库（已发生过一次：`docs/spec/TASK-005/` 37 KB，与规范 `docs/DESIGN-DETAIL.md` 重复，已删除）。
   **规范由决策者维护；实现者只写报告**（报告路径由任务书指定）。若你认为规范有误或缺失，
   **在报告里报缺陷**，不要另起一份规范。
3. **证据被证伪时要撤回**：若某项主张无法复现（例如「`--import` 崩溃」），必须在报告里**显式撤回**并标注，
   而不是悄悄删掉——append-only 勘误是允许且被鼓励的做法。
4. **「某工具是否在线」不得用 `-match`/文本包含判断**（M4 实测两次假 PASS）：
   契约里的 `description` **会互相按名引用**（例如「要扁平形态请用 `editor_list_signal_connections`」），
   因此「响应文本里出现该名字」**不等于**该工具已注册。
   → 必须**解析 `tools/list` 的 `name` 字段**后做集合判断，并与契约条目逐字比对。
5. **断言/期望值必须与「引擎实际语义」对齐后再写**：已发生过 `{"x":3,"y":4}` 与 `Vector2` 属性比较时
   报 `passed=false` 却打印两个相同值（期望值归一化缺陷）。写比较前先确认两边的**表示形式**。
6. **本 harness 的 doctest `REQUIRE` 不会中止用例**（`tests/test_macros.h:44`）→
   `REQUIRE` 之后的**每次读取/索引都必须自己守卫**，否则会以「读到空值」的形式产生**假绿**。
7. **「失败 → 默认值 → 报成功」这一类缺陷分两层判定，不得混为一谈**：
   「**声明的确定性转换**」不算该类（如整值 `FLOAT→INT` 截断、写入 `String` 目标时的字符串化、
   未知输入被忽略等），但**必须在报告里逐条声明**；
   「**槽位宽**」（`uint8`/`int32`/`float`/`real_t`）**必须与「转换关系」分开判定** ——
   `can_convert` 为真**不代表**值能落进槽位（已实证：`300→44`、`-1→255`、`3e9` 截断、`1e300→inf`、`1e-300→0`、`1e300→float 收窄`）。