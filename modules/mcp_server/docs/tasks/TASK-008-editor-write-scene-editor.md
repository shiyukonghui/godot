# TASK-008 — 移植组 `editor_write_scene_editor`（10 个工具，含 **fix_implementation_first**）

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（通用规范，自包含），再读本文件。
> 报告写到 `docs/reports/REPORT-008-editor-write-scene-editor.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 1. 组信息

- 组名：`editor_write_scene_editor`（`channel=editor`，`mutating=true`，**编辑器专有** → 9889 必须缺席）
- 成员（10 个，**新名以契约为准**）：

| 新名 | 旧名 | 关键点 |
|---|---|---|
| `editor_open_scene` | `open_scene` | 打开场景（编辑器状态变化；须能用 `editor_get_scene_tree` 佐证） |
| `editor_save_scene` | `save_scene` | 保存当前场景到磁盘（**写文件，须走原子发布**） |
| `editor_reload_plugin` | `reload_plugin` | 重载编辑器插件 |
| `editor_rescan_project_filesystem` | `reload_project` | 触发资源重新扫描 |
| `editor_set_node_selection` | `select_nodes` | 设置选中节点 |
| `editor_remove_node_selection` | `clear_editor_selection` | 清空选中 |
| `editor_add_resource_to_node_property` | `add_resource` | 给节点属性挂资源 |
| `editor_set_viewport_3d_camera` | `set_editor_camera` | 设置 3D 视口相机 |
| `editor_capture_screenshot` | `get_editor_screenshot` | **条件写**：`save_path` 非空即落盘（GDR-18 已按 `mutating=true` 记录） |
| `editor_remove_output_log` | `clear_output` | **`fix_implementation_first`！见 §2** |

## 2. `editor_remove_output_log` 的**先红后修**（本组最重要的一项）

迁移源**谎报**：它只 `godot_print!` 打印约 51 个空行、返回 `{"cleared": true}`，**Output 面板根本没被清空**。

1. **先写一条会失败的红测试**，证明「返回 `cleared:true` 但实际没有任何东西被清空」。
   （可观察量自选，例如：在编辑器日志里产生一条可识别消息 → 调用工具 → 再次读取日志/面板内容，
   断言该消息**确实消失**。红阶段必须贴出真实失败输出。）
2. 然后**修实现**，选择顺序如下：
   - **(a) 优先**：找到编辑器里**真实可用的清空路径**（例如 `EditorNode`/`EditorLog` 的日志清除接口，
     或 Output 面板所绑定的日志缓冲区），实现真正的清空，并用**前后对比**证明消息消失；
   - **(b) 退路**：若从模块确实无法触达真实清空路径，则**不得谎报** —— 改为返回
     `-32000 not_implemented` 并带 `data.suggestion`（说明为何不可达、可用的替代做法），
     并在报告里明确记录「该工具目前是诚实的失败，而不是假的成功」；
   - **(c) 禁止**：任何「返回 `cleared:true` 而实际未清空」的形态。
3. 若走 (b)，**契约/映射都不改**（工具仍在 171 条里），但报告必须把该决定与证据写清，供决策者在 M2 验收时复核。

## 3. 框架清理（先做，与其他写组共享）

`project_write_resource_scene` 组里的**原子发布助手**（临时文件 + 备份 + rename）目前是该组文件私有。
本组 `editor_save_scene` 也需要写文件 → **把它上提到共享助手**（`tools/tool_helpers.*`），
让两组共用，并给出**重构前后行为等价**证据（同一请求序列的响应逐字节相同）。
（TASK-005 已有同类先例，做法照旧。）

## 4. 其他要求

1. **编辑器专有**：全部走 `MCP_EDITOR_TOOLS_ENABLED` 守卫；在 **9889（游戏）** 上必须**全部缺席**，
   且在游戏进程调用任一工具必须得到 `-32601` 且**不执行**（给真实响应证据）。
2. **状态变化要可观察**：`editor_open_scene` / `editor_set_node_selection` / `editor_set_viewport_3d_camera`
   等改变编辑器状态的工具，必须用**后续读取工具**（`editor_get_scene_tree` / `editor_get_selection` /
   `editor_get_viewport_3d_camera`）给出「操作前 → 操作 → 操作后」的证据链。
3. **文件写入**：`editor_save_scene` 与 `editor_capture_screenshot`（`save_path`）必须走原子发布；
   失败**不得破坏原文件**（用只读/损坏文件做反例）。
4. 破坏性/写入操作只在 `%TEMP%` 的 **scratch 工程副本**上进行。
5. `docs/tool-groups.json` 的 `implemented` 置 `true`。

## 5. 门

按 `PLAYBOOK-group-port.md` §3 五道门（门①用 `-Group editor_write_scene_editor`，**逐端点 scope 语义**），
外加：§2 的红/绿证据、§3 的重构等价证据、§4 的证据链与游戏端点缺席证据。

## 6. 报告

按手册 §4，写到 `docs/reports/REPORT-008-editor-write-scene-editor.md`；
另加三节：「`editor_remove_output_log` 的红→修全程与最终语义」「原子发布助手上提的等价性证明」
「编辑器状态变化的前后证据链」。**返回值：≤15 行总结 + 报告路径。**