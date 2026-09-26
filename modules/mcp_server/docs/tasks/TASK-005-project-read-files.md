# TASK-005 — 框架清理（助手去重）+ 移植组 `project_read_files`（6 个工具）

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（通用规范，自包含），再读本文件。
> 报告写到 `docs/reports/REPORT-005-project-read-files.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 1. 第一部分：框架清理（**先做**，为后续组消除重复）

TASK-004 在 `tools/project_read_analysis.cpp` 里**重复实现了 4 个小助手**
（`_split_lines`、`_serialize_variant`、`_join_path`、扩展名遍历），原因是组文件内部链接的助手无法跨文件复用。
在剩余 5 个组开工前先把它清理掉，否则重复会成倍增长：

1. 把这 4 个助手**上提**到 `tools/tool_builder.h`（或 `tools/` 下新的共享头，命名与现有风格一致），
   作为 `MCPTools::` 命名空间内的公共助手；行为与现有实现逐字一致。
2. 让 `tools/project_read_analysis.cpp` 与 `tools/project_read_template.cpp` **改用共享助手**，
   删除各自的本地副本（若某组确实不需要某个助手，就只用不删）。
3. 断言「同一函数只有一个定义」：报告里贴 `grep` 结果证明不再有重复定义。
4. 门：doctest 全绿、全引擎 0 failed、契约子集（并集语义）全过 —— **重构不得改变任何可观察行为**。

## 2. 第二部分：移植组 `project_read_files`（6 个工具）

- 组名：`project_read_files`（`channel=project`，`mutating=false`，`scope=both`）
- 成员（**新名以契约为准**）：

| 新名 | 旧名 | 提示 |
|---|---|---|
| `project_list_scripts` | `list_scripts` | 脚本清单（类型/路径） |
| `project_read_script` | `read_script` | 读脚本内容（注意行号/编码） |
| `project_validate_script` | `validate_script` | 语法/结构校验（注意迁移源只是启发式，别把它说成编译器） |
| `project_read_resource` | `read_resource` | 读 `.tres`/资源（注意变体序列化保真） |
| `project_get_resource_preview` | `get_resource_preview` | 预览信息（尺寸/类型等） |
| `project_read_scene_file_content` | `get_scene_file_content` | 读 `.tscn` 文本内容 |

特别注意：
1. 全部**只读**；不得写任何项目文件（含 `.uid`）。
2. `project_read_script` / `project_read_scene_file_content` 的输出形状（是否含行号、字段名）**以契约为准**，
   并在报告里写出「迁移源可观察契约 vs C++ 实现」的对照。
3. 若其中某工具需要脚本语言支持（`ScriptServer`），注意 **doctest 进程不加载脚本语言**
   （`Main::test_setup()` 不调用 `init_languages()`）——这类正例用门②的**真实工程证据**承载，
   **不要**写「加载失败即跳过」的假通过测试。
4. 组清单 `docs/tool-groups.json` 的 `implemented` 置 `true`。

## 3. 门

按 `PLAYBOOK-group-port.md` §3 五道门执行（门①用 `-Group project_read_files`，并注意其**并集语义**）。
另需：重构前后的**行为等价**证据（同一组请求在重构前后返回逐字节相同的响应，至少覆盖已实现的两组各 3 个工具）。

## 4. 报告

按手册 §4，写到 `docs/reports/REPORT-005-project-read-files.md`；另加一节
「重构等价性证据」。**返回值：≤15 行总结 + 报告路径。**