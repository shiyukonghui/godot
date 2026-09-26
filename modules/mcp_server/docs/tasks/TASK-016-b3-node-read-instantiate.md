# TASK-016 — B3 续批：`_find_node` 上提 + 接下来 2 组（≤20 个工具）

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（通用规范，自包含），再读本文件。
> 报告写到 `docs/reports/REPORT-016-b3-node-read-instantiate.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 状态

已实现 **76** 个工具（B1 41 + B2 25 + B3 首组 10）。B3/B4/B5 manifest 已完备：
`docs/tool-groups-b3.json`(40/12 组) / `-b4.json`(7/3) / `-b5.json`(58/26)。

## 1. 第一部分：助手上提（先做，避免重复增长）

TASK-015 在 `tools/editor_node_write.cpp` 里**复制了一份 `_find_node`**（路径解析语义），
因为提升进共享助手需要改已验收的 B1 组文件（当时按纪律没做）。现在**必须**清理：

1. 把编辑器侧的**节点路径解析**（`_find_node` 及其依赖）上提到 `tools/tool_helpers.*`
   （与 `require_editor_ui`、`property_value_from_json` 等并列），**语义与现有一致**。
2. 让 **所有**已有调用者改用它（`editor_node_write.cpp` 与 B1 的编辑器组文件），删除各自的本地副本。
3. **证明等价**：与 TASK-005/TASK-008/TASK-009 的先例一致——同一请求序列在重构前后的**响应逐字节相同**
   （对照提交 = 重构前那一刻；贴出关键响应 sha256 与「同一函数只有一处定义」的 grep 结果）。
4. 若发现其他**跨组重复**的助手（属性写、路径归一、类型转换），一并按同一标准上提——但**不要**顺手改行为。

## 2. 第二部分：移植接下来 2 组（合计 ≤20 个工具）

从 `docs/tool-groups-b3.json` 里按**依赖顺序**取接下来的 **2 组**（建议优先 `editor_node_read`
——本组写族的读回半边——再取一组实例化/资源挂载类；**以 manifest 为准**，在报告里写明组名与成员清单）。

要求：
1. 全部仅经 `MCPTools::ToolBuilder` 注册；`channel`/`scope`/`mutating` 与映射一致；
   `scope=editor` 者**必须缺席于游戏端点 9889** 且游戏进程调用 `-32601` 不执行。
2. 每个工具**三类证据**（成功/缺参/底层失败）+ **每组一条跨工具活证据链**
   （读族：与 TASK-015 的写族互相验证——**用写族改、用读族读回**，这是最有价值的链条）。
3. 未知属性/不存在节点一律 `-32001`（**不得**产出成功形状）；节点写复用一个共享的
   `write_node_property`（TASK-014 确立的「先查属性表再写」形状），**不要**再复制一份。
4. 破坏性/写入操作只在 `%TEMP%` scratch 工程副本上进行（`.tscn` **不要写 BOM**）。
5. `docs/tool-groups-b3.json` 里对应两组的 `implemented` 置 `true`。

## 3. 门

按 `PLAYBOOK-group-port.md` §3 五道门（**门①按两组各跑一次**；第 0 步先校验 `--version` == HEAD，不一致先重建），
外加：§1 的等价性证明、§2 的写读互验活证据链与 scope 缺席证据。

## 4. 报告

按手册 §4，写到 `docs/reports/REPORT-016-b3-node-read-instantiate.md`；另加：
「助手上提的逐字节等价证明」「写族→读族互验链条」「本批后已实现工具总数与剩余计数」。**返回值：≤15 行总结 + 报告路径。**