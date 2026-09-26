# TASK-024b — 顺手性批次 2（拆小后）：**E-1+G-2**（依赖类型与可喂回的 path）· **E-3**（读回形状一致）

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（自包含），再读本文件；
> **规范落笔见 `docs/DESIGN-DETAIL.md` §23 / GDR-25**（顺手性的可执行判据：**零字符串手术链**）。
> 报告写到 `docs/reports/REPORT-024b-ergonomics-batch2.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 拆分背景（读一下，避免重蹈覆辙）

原 **TASK-024** 把 5 个顺手性项塞进一个任务，**执行者耗尽上下文失败**（D77：工作树留下不一致半成品，已回退）。
教训：**一个上下文装得下**才算一个任务。本任务**只做两项**（E-1+G-2、E-3），且**都不改输入 schema**
（只改**输出形状**与**内部取数方式**），因此**不应触发契约重生成**（若你发现必须动 `inputSchema`，**停下来在报告里报缺陷**）。

## 1. E-1 + G-2：`project_get_scene_dependencies` 的 `type` 与 `path`

**现状（实测，M4c）**：`type` **不是类型而是 fallback 路径**（`"type":"res://main.gd"`）；
`path` 是 **`uid://c7mt5x5j361vt`** → 调用方必须**额外走一趟** `project_convert_uid_to_path` 才能把结果喂给别的工具
（**违反 GDR-25 §23.1 禁止事项 1**）。

**引擎正解（M4c 给出）**：`scene/resources/resource_format_text.cpp:919/960-968`
（`p_add_types` 会让依赖串变成 `path::type::fallback`）、`core/io/resource_loader.h:266/270`
（静态 `get_resource_type`、`get_dependencies(..., p_add_types=false)`）；`ResourceUID::uid_to_path` 做归一化。
**请自己复核这些位置**（引擎源码是第一参考源，M4c 的行号只是线索）。

**要求**：
1. `type` 必须是**真实类型**（切分正确；`fallback` 的语义要按引擎实际含义处理并写清）。
2. `path` 与 `uid` **都要给出**（或让 `path` 直接是 `res://…`），使结果**可直接喂回**其它工具。
3. 报告给出「**改前几趟 / 改后几趟**」对照，以及「把 `path` 直接喂给下一个工具」的**实测**。

## 2. E-3：`Vector4` 与 packed 的读回形状与 `Vector2` 家族不一致

**现状（实测，M4c）**：`serialize_variant`（`tools/tool_helpers.cpp` 约 94-200）给
`Vector2/2i/3/3i/Color/Rect2` 专门分支；**`Vector4` 与全部 packed 走 default → 变成字符串**
（`v4="(5.0, 6.0, 7.0, 8.0)"`、`pv2="[(1.0, 2.0)]"`）→ 同一份读回里 `position` 是对象、`v4` 是字符串，
**消费者必须分支处理**（**违反 GDR-25 §23.1 禁止事项 4**）。

**要求**：
1. 为 **`Vector4`/`Vector4i` 与全部 packed 类型**加**显式分支**，形状与 `Vector2` 家族**一致**且**可预测**。
2. `PackedStringArray` / `PackedByteArray` 的语义**按引擎语义**决定（字节数组给什么形态最可复现、最可用），
   并在报告里说明理由。
3. **必须区分并声明**：M4c 发现「未写过的新场景上 packed 导出默认值读回 `null`」是**引擎行为**
   （模块与独立 GDScript 观测一致）→ **不是本项要修的缺陷**，报告里**不得**把它算作成果。
4. **兼容性检查**：形状变更会影响**既有 doctest 与证据脚本**（例如 B2/B3 里断言 packed 为字符串的用例）——
   全部要更新，并在报告里**列出受影响的测试与证据**。

## 3. 通用要求

1. **不改名字**；**不改 `inputSchema`**（只改输出/取数）；若认为必须改 → 报缺陷，不要自行改契约。
2. 每项给 **现状 → 引擎正解（API+行号）→ 改后** 对照。
3. **顺手性自评**：写一条真实执行过的**零字符串手术链**（≥4 步，跨工具），
   **逐步标出调用方字符串处理次数（目标 0）**，并说明本批如何把它从 >0 降到 0。
4. 更新 `docs/DESIGN-DETAIL.md` **只在必要时**（例如 E-3 的形状表要登记）——
   **若需要，报给决策者**，不要自行写规范章节（规范由决策者维护）。

## 4. 门

- 第 0 步：`scripts/build_local.cmd -Force`（`tests=yes`）重建 + 校验 `--version` == HEAD。
- 五道门 + **门⑥**（第 0 步之后、构建通过即跑）。
- 回归：`project_get_scene_dependencies` 在**至少两个不同场景**上的结果（含一个含脚本依赖的）；
  E-3 的形状在 **编辑器侧与游戏侧**都验证（各 ≥3 种 packed + `Vector4`）。

## 5. 报告

按手册 §4（含「引擎依据」列），写到 `docs/reports/REPORT-024b-ergonomics-batch2.md`；另加：
「每项：现状→引擎正解→改后」「零字符串手术链（含字符串处理次数）」「受形状变更影响的测试/证据清单」
「本批后仍未处理的顺手性项（E-9/E-6/G-4/E-2/E-8/G-1/G-3）」。**返回值：≤15 行总结 + 报告路径。**