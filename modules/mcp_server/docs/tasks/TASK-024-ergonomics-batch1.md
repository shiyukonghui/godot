# TASK-024 — 顺手性批次 1（GDR-23）：E-10 端口转发 · E-1 依赖类型 · E-3 读回形状 · E-9 资源内容 · E-6/G-4 日志来源

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（自包含；**§6 总纲/§6.10 已是「引擎优先 + 顺手性是验收条款」**），
> 再读本文件。独立验收原文：`docs/reports/REPORT-AUDIT-M4c.md`（**§2.F 与 §10 有你需要的引擎行号**）。
> 报告写到 `docs/reports/REPORT-024-ergonomics-batch1.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 本批的性质（与以往不同）

以往任务是「移植工具」；本批是**按 GDR-23 把已验收工具改成引擎自然形态**。
**判据是「顺手」**：调用方应当**一趟做完引擎一趟能做的事**，且**整条链不需要手工字符串处理**
（不需要手动把 `uid://` 换成 `res://`、不需要再解析 `Vector4` 的字符串、不需要从路径里剔 `@EditorNode@…`）。
每项都要给：**现状（要几趟/要什么手工处理）→ 引擎正解（API + 行号）→ 改后（一趟）** 的对照。

## 1. **E-10（最高优先）**：`editor_play_scene` 不转发 `--mcp-port`

- **现状**：编辑器启动的游戏子进程 cmdline **没有** `--mcp-port`（实测含 `--path/--remote-debug/--editor-pid/--scene`），
  游戏只能读 `ProjectSettings: godot_mcp/port` → **想让游戏可被观察就得改被测工程设置**。
- **引擎正解（审计方给出）**：`editor/run/editor_run_bar.h:117/123-125` 的
  `play_main_scene/play_current_scene/play_custom_scene(..., const Vector<String> &p_play_args)`；
  `editor_run_bar.cpp:355-364` 把 args 交给 `editor_run.run()`。
  （另注：`editor_node.cpp:7797 → editor_plugin.h:218 run_scene(scene, args)` 是**给 EditorPlugin 的钩子**，
  内置模块通常走 `EditorRunBar` 单例即可。）
- **要求**：
  1. `editor_play_scene` 启动游戏时**注入** `--mcp-port=<端口>`，使**编辑器起的游戏立刻可被 MCP 观察**，
     **不需要改被测工程**。
  2. **端口选择要顺手且不冲突**：编辑器自己的端口不能再给子进程用（会 bind 失败）。
     设计成：**可选参数 `mcp_port`**（调用方可指定，便于自动化用固定端口）；
     **缺省时由模块自动挑一个空闲端口**（并保证与编辑器自身端口不同）。
  3. **响应必须告诉调用方游戏端点在哪**（例如 `mcp_port` + 可直连的 URL/`pid`），
     使调用方能**立刻**连上，而不是去猜或去读日志。
  4. 若确实无法注入（引擎侧 guard、非编辑器进程等），**诚实报错**，不得假装成功。
- **契约影响（允许，走既有机制）**：新增可选参数属**输入 schema 变更** →
  必须用 `SCHEMA_OVERRIDES`（理由进 `_meta.overrides`）**重生成契约 + 重渲染 `TOOL-NAMING.md` + 更新指纹**，
  并让门① 在两端点上**逐字通过**。**不得**手改契约文件。

## 2. E-1 + G-2：`project_get_scene_dependencies` 的 `type` 与 `path`

- **现状**：`type` 不是类型而是 **fallback 路径**（实测 `"type":"res://main.gd"`），`path` 是 **`uid://c7mt5x5j361vt`**
  → 调用方**必须额外走一趟** `project_convert_uid_to_path` 才能把结果喂给别的工具。
- **引擎正解**：`scene/resources/resource_format_text.cpp:919/960-968`（`p_add_types` 会追加 `::type`，
  带 uid 时为 `path::type::fallback`）、`core/io/resource_loader.h:266/270`
  （静态 `get_resource_type`、`get_dependencies(..., p_add_types=false)`）；
  另 `ResourceUID::uid_to_path` 做归一。
- **要求**：`get_dependencies(..., p_add_types=true)` + 正确切分 `parts` → **`type` 为真实类型**；
- **要求**：`path` 归一并**同时**给出 `uid` 与 `path`（或让 `path` 直接是 `res://…`），
  使结果**可直接喂回**其它工具（**链式喂回**）。报告给出「改前几趟 / 改后几趟」对照。

## 3. E-3：`Vector4` 与 packed 的读回形状与 `Vector2` 不一致

- **现状**：`serialize_variant`（`tools/tool_helpers.cpp:94-200`）给 `Vector2/2i/3/3i/Color/Rect2` 专门分支，
  **`Vector4` 与全部 packed 走 default → 变成字符串**（`v4="(5.0, 6.0, 7.0, 8.0)"`、`pv2="[(1.0, 2.0)]"`），
  同一份读回里 `position` 是对象、`v4` 是字符串 → 消费者要**分支处理**。
- **要求**：为**所有 `Vector4`/`Vector4i` 与全部 packed 类型**加**显式分支**，形状与 `Vector2` 家族**一致**
  （例如 `[x,y,z,w]` / `[[x,y],[x,y]]` / 数值数组），使消费者**不需要分支**。
- **注意**：`PackedStringArray`/`PackedByteArray` 的语义（字节 vs 字符串）要**按引擎语义**决定并写清。
- **明确区分**：审计发现的「未写过的新场景上 packed 导出默认值读回 `null`」是**引擎行为**
  （模块与独立 GDScript 观测一致）→ **不是本项缺陷**；报告里要**声明**这一点，不要把它算成修好的东西。

## 4. E-9：`project_read_resource` 只回 `{loaded,path,type}`，**不给内容**

- **现状**：读资源却不给属性值，调用方只好再走一趟 `editor_execute_gdscript` 去 `get_property_list()`。
- **要求**：在响应里给出资源的**属性值**（引擎侧 `get_property_list()` 中 `STORAGE` 可用者；
  实测 `Curve` 有 7 个 STORAGE 属性），字段命名与既有「读属性」工具**一致**（复用同一序列化路径），
  并**限量**（给出上限与截断标记，避免巨大资源把响应撑爆）。

## 5. E-6 + G-4：日志工具的**来源**与**即时性**

- **现状**：`editor_read_scene_inspector.cpp:71` 硬编码 `user://logs/godot.log`，只读文件；
  实测**编辑器端点读到的是游戏进程的行**（`port 9889`、`editor=false`、`source=log_file`），
  且轮转窗口里直接 `-32603`（**非诚实空**）。而 `editor_remove_output_log` 走的是**进程内** `EditorLog`（`editor/editor_log.h:182`）
  → 语义分裂。
- **要求**：
  1. **优先走进程内 `EditorLog`**（同一侧语义与 `editor_remove_output_log` 一致），
     文件读取仅作为**后备**，并在响应里**标明来源**（`source: "editor_log" | "log_file"`）**与所属进程**
     （至少 `editor: true/false` 与端口/pid），使调用方**不会把别的进程的日志当成自己的**。
  2. **不可用时要诚实**：返回**空 + 说明**（或明确的 `-32000` + 建议），**不得**用 `-32603` 掩盖「读不到」。
  3. **G-4**：`editor_get_errors` 与 `editor_get_output_log` 的**返回形状统一**（两者都应带同一组来源字段）。

## 6. 通用要求

1. 全部改动必须**不改名字**；需要改 schema 的**只**走 override 机制（见 §1）。
2. 每项给出**改前/改后对照**（趟数、需不需要手工字符串处理）+ **引擎依据（API + 行号）**。
3. **顺手性自评**：写一条「**零字符串手术链**」示例（例如：起游戏 → 拿端口 → 连上 → 读依赖 →
   把 `path` 直接喂给下一个工具 → 读资源拿属性），逐步列出**调用方需要做的字符串处理次数（目标：0）**。
4. 更新 `docs/DESIGN-DETAIL.md`：把「顺手性条款的可执行判据（零字符串手术）」与
   「日志类工具必须声明来源进程」写入（可扩展 GDR-23 或新增 GDR-25）。

## 7. 门

五道门 + **门⑥**（第 0 步：`scripts/build_local.cmd -Force`（`tests=yes`）重建 + 校验 `--version` == HEAD），
外加：§1 的**子进程 cmdline 实测含 `--mcp-port` 且游戏端点**真的可达（从该端口跑一个游戏侧工具）、
§2..§5 的改前/改后对照与引擎依据、§6.3 的零字符串手术链。

## 8. 报告

按手册 §4（报告格式含「引擎依据」列），写到 `docs/reports/REPORT-024-ergonomics-batch1.md`；另加：
「每项：现状→引擎正解→改后 的对照表」「零字符串手术链（含字符串处理次数）」
「契约 override 的 `_meta` 与重生成指纹」「本批后仍未处理的顺手性项（E-2/E-8/G-1/G-3 等）」。
**返回值：≤15 行总结 + 报告路径。**