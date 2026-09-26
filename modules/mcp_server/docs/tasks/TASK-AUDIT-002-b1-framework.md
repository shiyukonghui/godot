# TASK-AUDIT-002 — 独立验收：B1 框架 + 6 工具模板组 + 全 B1 组清单 + 映射 v1.2

> **执行者须知**：你是**独立验收方**，没有参与实现，**不得采信实现方与决策者的任何结论**——
> 只依据规范、代码与你**自己可复现**的证据。上一轮同类验收（TASK-AUDIT-001）判出过 3 类真实缺陷，
> 本轮同样要求对抗性核对。
>
> 完成后**必须**把完整报告写到 `docs/reports/REPORT-AUDIT-002-b1-framework.md`，
> 返回给决策者的内容**只允许**是「简洁总结（≤15 行）+ 报告路径 + verdict」。

## 1. 验收对象与实现方声称

| 对象 | 路径 | 实现方声称 |
|---|---|---|
| 期望契约 v1.2 | `docs/tools_list.renamed.json` | 98923 B，sha256 `898d868278147cb6f11e83fe11e4e065fb9aa66d13b0a801d81a89354618d57b`，171 条 |
| 规范文档 | `docs/TOOL-NAMING.md` | 98462 B，sha256 `f68f1551dc01a72331ae9b1590a8ed9167102c10a947a8f1607bfae0b2561d59` |
| B1 组清单 | `docs/tool-groups.json` | 5443 B，sha256 `9644911a01e983e69074b7988462789388e2dc59e17c74308fabb368d2ab0e59`，**41 个工具 / 7 组** |
| 映射 | `docs/tool-rename-map.json` | 未改动（70917 B，`2f552719…`） |
| 框架 | `tools/registration.{h,cpp}`、`tools/tool_builder.h`、各组 `tools/<group>.{h,cpp}` | 见 `docs/DESIGN-DETAIL.md` **§17 / GDR-19** |
| 实现报告 | `docs/reports/REPORT-002-b1-framework.md` | 实现方的自述（**待你核验，不是证据**） |

模板组（6 个）：`project_get_info`、`project_get_settings`（迁移，`tools/list` 应逐字不变）、
`project_get_filesystem_tree`、`project_search_file_names`、`project_search_file_contents`、
`project_find_files_referencing_symbol`（4 个新实现；后两者是**取消合并后的独立工具**）。

工程门声称：doctest **53/53（410 断言）**、全引擎 **1479 passed / 0 failed / 3 skipped**、
`accept_m1.ps1` **21/21 连跑两次**、`scripts/check_contract_subset.ps1 -Group project_read_template` 在 **9888 与 9889** 上逐字 **6/6**。

## 2. 规范依据（只读）

`docs/DESIGN-DETAIL.md`（§10 B1 清单、§16 执行顺序、§17/GDR-19 框架、GDR-16 lint、GDR-17 合并不损、
GDR-18 条件写、GDR-6/14 错误语义）、`docs/tasks/TASK-002-b1-framework.md`（任务书）、
`F:\moonbit-hof-rs\DECISIONS.md`（D38/D41/D43/D44/D45/D46）、迁移源 `godot_mcp_gdext/src/commands/*.rs`（只读）。

## 3. 必须核实（逐条给结论 + 证据）

### 3.1 预备项
1. **7 条 description 判别点**（R-1/R-2/R-3）确实存在于 `tools_list.renamed.json`，且
   **逐条对回迁移源码核实为真**（不是编造）：
   `editor_analyze_signal_flow` / `editor_list_signal_connections` /
   `project_search_file_names` / `project_search_file_contents` / `project_find_files_referencing_symbol` /
   `project_convert_uid_to_path` / `project_convert_path_to_uid`。
   请自行判断：**只看名字 + description，一个智能体能否可靠二选一**？给出每对的裁决。
2. **nit N-1**：`TOOL-NAMING.md` 的 `disposition` 单元格是否已是**纯枚举值**（不再有「→目标」装饰）；
   174 行表格是否仍与映射逐字段 0 不一致；头部指纹是否与新契约一致。
3. **nit R-4**：`accept_m1.ps1` 的 SUMMARY 是否打印「已实现 N / 契约 171」并标注 `known_deviation`。
   **自行确认该脚本的逐字对等门实际覆盖范围**（是全部已实现工具，还是仅 `$ToolNames`？实现方上一轮自报只有 2 个，本轮应为 6 个——请核实）。

### 3.2 框架
4. `registration.{h,cpp}` 是否**只有** `register_all_tools()` 且每组一行；组文件是否**各自独立**（组间无共享文件）。
5. `ToolBuilder` 是否**强制**显式声明 `channel/verb/scope/mutating`（缺失即拒绝注册）——
   请**实际构造一个违规用例**证明它真的会拒绝（例如临时测试里省略 `mutating`），而不是只看代码。
6. 参数校验三类错误路径：`require_*` 缺参 → `-32602`；`optional_*` 存在但类型错 → `-32602`（实现方称比参照实现更严）。
7. **编辑器守卫**：`MCP_EDITOR_TOOLS_ENABLED` / `TOOLS_ENABLED` 的用法是否正确
   （本 fork 中 `TOOL_ENABLED` 是否真的不存在？请自己 grep 确认，不要采信报告）；
   游戏进程是否**确实不注册** `scope=EDITOR` 工具（用 9889 端点实际验证）。
8. `normalize_project_path` 的安全边界：`..`、绝对路径、空段、尾斜杠——**自己构造反例**验证；
   是否存在可读写项目根之外的路径的绕过方式（这是安全问题，请尽力找）。

### 3.3 模板组行为
9. 两个迁移工具（`project_get_info`/`project_get_settings`）的 `tools/list` 条目与 v1.2 契约**逐字相等**；
   迁移前后行为无回归（`project_get_info` 在**游戏进程**下的回退路径也要核）。
10. **`project_search_file_contents` 与 `project_find_files_referencing_symbol` 必须是两个不同实现**：
    自己构造同一工程同一输入，验证输出形状（逐行 `{file,line,text}` vs 按文件聚合 `{file,lines[]}`）、
    大小写敏感度（不敏感 vs 敏感）、上限（**50 vs 100**）三项差异**真实存在**。
    实现方称「同一输入 3 命中 vs 0 命中」——请独立复现（或推翻）。
11. `project_search_file_names` 是否**只按文件名**匹配（不得搜内容）；上限 200 是否真实生效（自己造 >200 命中的工程）。
12. 三类证据（成功/缺参/底层失败）是否**真实可复现**：自己用 `curl.exe --data-binary @file` 打 9888，
    抽 3 个工具各验一遍（**注意**：JSON body 作为 Windows 命令行参数会丢引号 → 必须用文件）。

### 3.4 组清单与工程门
13. `docs/tool-groups.json`：41 个工具是否**恰好各出现一次**（双向差集为空）；是否与
    `DESIGN-DETAIL.md` §10 的 B1 清单（42 旧 − `get_editor_performance`）**等价**；
    每组是否一个 channel + 一个 mutating 值、组 ≤10；名字是否都存在于契约。
    **自己重算**，不要复用 `docs/scripts/check_tool_groups.py` 的结论。
14. 工程门自己跑：`--test --test-case=[MCPServer]*`、全引擎 `--test`、`accept_m1.ps1` ×2、
    `check_contract_subset.ps1 -Group project_read_template`（编辑器 + 游戏）。
15. **反例工作**：`docs/tool-groups.json` 的分组对后续**并行**移植是否真的安全
    （组间无共享文件？**注意**：所有组都要改 `registration.cpp` 的同一处——请判断这在
    「多子代理共享同一工作树」的现实下是否会构成冲突，并给出建议）。

### 3.5 实现方 deviations（**逐条裁决建议**，实现方列了 9 条）
重点看这几条是否可接受：`path` 不存在返回 `-32001`（参照实现是静默空结果）、
`optional_*` 对「存在但类型错」返回 `-32602`（参照实现静默忽略）、
新增 `GDR-19/§17` 到 `DESIGN-DETAIL.md`、`TOOL_ENABLED`→`MCP_EDITOR_TOOLS_ENABLED` 的等价替换。

## 4. 硬性约束

- **不得修改任何文件**（含被验收件与脚本）；临时脚本与输出放 `%TEMP%\audit002\**`。
- 不得 git 写操作；不得安装依赖；**绝不占用 9877**（用户正在用的 Godot 4.7.1-mono，PID 36392）；测试端口 9888/9889。
- 若你需要「实际构造违规用例」来验证 ToolBuilder，**只允许临时改测试文件并在验证后还原**（报告里必须写明还原的证据：`git status` 干净）。
- 所有结论必须附真实命令输出或源码行号；严格区分「证据支持」与「推断」；不确定写 `unconfirmed`。

## 5. 报告要求（写到 `docs/reports/REPORT-AUDIT-002-b1-framework.md`）

- `verdict`（机械/行为/工程门**分开判定**）、`verdict_scope`
- 上面 15 项逐条结论（含你构造的反例与真实输出）
- 7 条判别点的**独立裁决**（够不够让智能体二选一）
- `defects`（severity / claim / evidence / location / recommendation）
- 对 9 条 deviations 的逐条裁决建议
- `unverifiable`、`risks`、`next_step_recommendation`

**返回给决策者**：≤15 行总结 + 报告路径 + verdict。