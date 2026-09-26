# TASK-004 — 移植组 `project_read_analysis`（7 个工具）

> 执行者须知：本文件**只规定本组特有内容**；通用规范见
> `docs/tasks/PLAYBOOK-group-port.md`（**必须先完整阅读**，它是自包含的）。
> 完成后报告写到 `docs/reports/REPORT-004-project-read-analysis.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 1. 组信息

- 组名：`project_read_analysis`（`channel=project`，`mutating=false`，`scope=both`）
- 成员（7 个，**新名以契约为准**）：

| 新名 | 旧名 | 迁移源提示 |
|---|---|---|
| `project_get_statistics` | `get_project_statistics` | 统计脚本/场景/资源数量与行数 |
| `project_analyze_scene_complexity` | `analyze_scene_complexity` | `analysis.rs`；**`path` 为空时回退当前编辑场景**（编辑器专有分支 → 注意守卫），主契约是磁盘 `.tscn` |
| `project_detect_circular_dependencies` | `detect_circular_dependencies` | 脚本/场景依赖环检测 |
| `project_find_unused_resources` | `find_unused_resources` | 扫描 `res://` 找未被引用的资源 |
| `project_find_script_references` | `find_script_references` | `analysis.rs`；返回**逐行 `content` + `files_searched`**（与 `project_search_file_contents` 契约不同，**不要复用后者的实现**） |
| `project_get_scene_dependencies` | `get_scene_dependencies` | `.tscn` 的外部资源依赖 |
| `project_get_scene_exports` | `get_scene_exports` | 场景中 `@export` 变量清单 |

## 2. 本组特别注意

1. 这 7 个都是**只读**且作用于**项目磁盘**（`res://`）；不得写任何文件。
2. **`project_analyze_scene_complexity`** 的编辑器回退分支必须用 `MCP_EDITOR_TOOLS_ENABLED` 守卫；
   游戏进程下 `path` 为空时应返回明确错误（不得崩溃）。
3. **`project_find_script_references`** 与已实现的 `project_search_file_contents` **语义不同**：
   前者的返回形状是「逐行内容 + `files_searched` 计数」，不得实现成同一个（GDR-17 精神）。
4. 扫描类工具（`find_unused_resources` / `detect_circular_dependencies` / `get_scene_dependencies`）需在
   **一个自造的 scratch 工程**上验证（含循环依赖与未引用资源各至少 1 例）；scratch 放 `%TEMP%`。
5. 契约里的 `description` 已包含上一轮补充的判别点（若有），**以契约为准、逐字相等**。

## 3. 顺带修掉的两个小项（源自 TASK-AUDIT-003）

1. `scripts\accept_m1.ps1`：新增一项检查「**`tools/list` 跨进程重启一致**」——
   启动两个**独立**的引擎进程（各自 9888），比较两次 `tools/list` 响应体**逐字节相同**
   （现有检查只覆盖同进程内的确定性）。
2. `docs/reports/REPORT-002-b1-framework.md`：在 §10（勘误段）**追加一行**，指出该报告第 194 行
   「禁 `..` 与空段」的注释已过期，现行权威为 `docs/DESIGN-DETAIL.md` §17.2。
   **保持 append-only 约定，不要删改原文。**

## 4. 门

按 `PLAYBOOK-group-port.md` §3 执行，其中门①使用 `-Group project_read_analysis`，
门⑤（`accept_m1.ps1` ×2）需包含上面新增的跨进程一致性检查且**两次都通过**。

## 5. 报告

按 `PLAYBOOK-group-port.md` §4，写到 `docs/reports/REPORT-004-project-read-analysis.md`。
**返回值：≤15 行总结 + 报告路径。**