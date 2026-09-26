# TASK-007 — 契约描述纠正 + 移植组 `project_write_resource_scene`（4 个**写**工具）

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（通用规范，自包含），再读本文件。
> 报告写到 `docs/reports/REPORT-007-project-write-resource-scene.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 1. 第一部分：纠正契约里的一处**描述与行为不符**（决策者已裁决要改）

`editor_analyze_signal_flow` 的契约 `description` 写着按 `flags & 1` 判「持久连接」，
但在 **Godot 4** 里 `CONNECT_DEFERRED = 1`、`CONNECT_PERSIST = 2` —— 照字面实现会让普通场景**恒返回 `nodes: []`**
（TASK-006 已实测并报告，其实现按**意图**用了 `CONNECT_PERSIST`，但描述保持逐字未动）。

用户的明确要求是「**工具名/描述必须与功能对应**」，因此**描述要改对**：

1. 在 `scripts/gen_renamed_contract.py` 的 **`DESCRIPTION_OVERRIDES`** 表里为 `editor_analyze_signal_flow` 登记修正后的描述，
   **理由写进 `_meta.overrides`**（该机制已存在，见 TASK-001/B0）。
   修正文本要点：**只收集持久连接（`CONNECT_PERSIST`，值为 2）**；并显式提醒
   「注意 Godot 4 中 `flags & 1` 是 `CONNECT_DEFERRED`，不是持久连接」。
   **不要**改 `tool-rename-map.json`（避免映射 sha 漂移）；用 override 机制。
2. 重跑生成器得到新契约；**同步**修改该工具在 C++ 侧的描述字面量
   （`tools/editor_read_scene_inspector.cpp` 里那处 raw string，必须与新契约**逐字相同**，
   否则门①会失败——这正是门①的价值）。
3. 重渲染 `docs/TOOL-NAMING.md`（生成器 + 头部指纹同步）。
4. 断言：契约仍 **171 条**；受影响的行只有该工具；`_meta.overrides` 里能看到这条理由。

## 2. 第二部分：规范补充（`docs/DESIGN-DETAIL.md` §17.3）

把 TASK-006 引入的**按端点推导期望工具集**的规则写进规范：
「`scope` 决定端点可见性：`scope=editor` 的工具**只能**出现在编辑器端点（9888），
`scope=game` 只能出现在游戏端点（9889），`scope=both` 两端都出现；门脚本按 `tool-rename-map.json` 的 `scope`
**逐端点**推导期望集合并断言『editor-only 在游戏端点必须缺席』。」

## 3. 第三部分：移植组 `project_write_resource_scene`（4 个**写**工具，`mutating=true`）

**本组是第一个写组**，纪律要求更高：

| 新名 | 旧名 | 提示 |
|---|---|---|
| `project_create_resource` | `create_resource` | 建 `.tres`（类型/路径/初始属性） |
| `project_create_scene_file` | `create_scene` | 建 `.tscn` |
| `project_delete_scene_file` | `delete_scene` | 删场景文件（**破坏性**） |
| `project_edit_resource` | `edit_resource` | 改资源属性并落盘 |

硬性要求：
1. **不得破坏既有文件**：写操作走「先写临时文件、成功后原子改名」或等价的 Godot API；
   失败时**不得**留下半成品、**不得**破坏原文件（用一个「只读/损坏」的既有文件做反例验证）。
2. **路径安全**：新增文件必须落在 `res://` 内（复用 `normalize_project_path`）；
   不得允许 `..` 逃逸；不得写到项目外。
3. **删除必须是可观察且可核对**的：返回被删路径；不存在 → `-32001`（带 `data.suggestion`）；
   删除后断言文件系统状态（前后文件清单 + 目标文件不存在）。
4. **证据必须含真实文件系统变化**：每个工具一组「操作前清单/sha256 → 请求 → 操作后清单/sha256」，
   在 **%TEMP% scratch 工程**上进行（**不得**在仓库或用户工程里做破坏性操作）。
   注意：scratch 工程要用**副本**，且在报告里给出 scratch 路径与关键文件哈希。
5. `scope` 按契约（应为 `both`）；`mutating=true` 必须显式声明。
6. 组清单 `docs/tool-groups.json` 的 `implemented` 置 `true`。

## 4. 门

按 `PLAYBOOK-group-port.md` §3 五道门（门①用 `-Group project_write_resource_scene`，含**逐端点 scope 语义**），
外加本文件 §3 的文件系统变化证据与「失败不破坏原文件」的反例证据。

## 5. 报告

按手册 §4，写到 `docs/reports/REPORT-007-project-write-resource-scene.md`；
另加两节：「契约描述纠正的前后对照与 override 理由」与「写操作的文件系统证据 + 失败不破坏反例」。
**返回值：≤15 行总结 + 报告路径。**