# TASK-006 — 移植组 `editor_read_scene_inspector`（7 个**编辑器专有**只读工具）

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（通用规范，自包含），再读本文件。
> 报告写到 `docs/reports/REPORT-006-editor-read-scene-inspector.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 1. 组信息

- 组名：`editor_read_scene_inspector`（`channel=editor`，`mutating=false`）
- 成员（7 个，**新名以契约为准**）：

| 新名 | 旧名 | 提示 |
|---|---|---|
| `editor_get_errors` | `get_editor_errors` | 读 `user://logs/godot.log`（**不是**编辑器控件） |
| `editor_get_output_log` | `get_output_log` | 同上，支持过滤 |
| `editor_get_open_scripts` | `get_open_scripts` | 已打开脚本清单 |
| `editor_get_scene_tree` | `get_scene_tree` | 编辑场景树（注意深度/节点上限与字段形状） |
| `editor_get_selection` | `get_editor_selection` | 当前选中节点 |
| `editor_get_viewport_3d_camera` | `get_editor_camera` | 3D 视口相机位置/旋转 |
| `editor_analyze_signal_flow` | `analyze_signal_flow` | **取消合并后的独立实现**：按节点嵌套、**仅持久连接**（`flags & 1`）、`node_path` **精确**匹配；与 `editor_list_signal_connections`（B3 组）不是同一个 |

## 2. 本组是**第一个 scope=editor 的组**——必须补上一直缺失的端到端证据

此前 B1 的工具都是 `scope=both`，所以「游戏进程不暴露编辑器工具」这条守卫**从未被端到端验证过**
（TASK-AUDIT-002 已把这一点记为 unverifiable）。本组必须把它钉死：

1. 在 **9889（游戏进程）** 上：`tools/list` **不得包含本组任何一个工具**
   （同时整个已实现并集在 9889 上必须只剩 `scope` 允许的那些）。
2. 在 **9888（编辑器）** 上：本组 7 个工具必须全部出现且与契约逐字相等。
3. 报告里给出两次 `tools/list` 的**工具名清单对比**（编辑器有 / 游戏无），作为守卫的端到端证据。
4. 顺带核实：`MCP_EDITOR_TOOLS_ENABLED` 编译期守卫与 `is_editor_process()` 运行期守卫**是否都真的起作用**
   （构造一次「游戏进程试图调用编辑器工具」的请求，必须得到 `-32601` 或明确的拒绝，**不得**执行）。

## 3. 顺带修掉的小项

1. **长度单位统一**（手册 §6 第 9 条）：检查已实现组里所有返回 `size` 的字段是否为 **UTF-8 字节数**；
   若是字符数（TASK-005 报告已登记 `project_read_script` / `project_read_scene_file_content` 的 `size` 为字符数），
   **改为字节数**并同步更新 doctest 与报告；**契约若明确写了字符数则保持不动**（以契约为准，并在报告说明）。
2. 检查 `editor_get_errors` / `editor_get_output_log` 读取的日志文件在**游戏进程**下的可用性
   （它们不出现在游戏的 `tools/list` 里，但实现不得在游戏进程启动时崩溃）。

## 4. 门

按 `PLAYBOOK-group-port.md` §3 五道门（门①用 `-Group editor_read_scene_inspector`，注意**并集语义**），
外加 §2 的编辑器/游戏可见性证据。

## 5. 报告

按手册 §4，写到 `docs/reports/REPORT-006-editor-read-scene-inspector.md`；
另加一节「editor scope 端到端守卫证据」。**返回值：≤15 行总结 + 报告路径。**