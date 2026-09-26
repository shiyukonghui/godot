# TASK-AUDIT-003 — 独立验收：框架修复与加固（TASK-003）

> 你是**独立验收方**，未参与实现，**不得采信实现方与决策者的结论**（`docs/reports/REPORT-003-framework-fixes.md` 是自述，不是证据）。
> 报告写到 `docs/reports/REPORT-AUDIT-003-framework-fixes.md`；返回值**只允许**是「≤10 行总结 + 报告路径 + verdict」。

## 验收对象（实现方声称）

契约 v1.3 `docs/tools_list.renamed.json` = 98953 B / sha256 `64723fb9fbe8247512171ee4ae8b6950486bad3722cb957091414b73ecf573f5`（171 条，`_meta.order_normative=false`）；
`docs/TOOL-NAMING.md` = 98720 B / `ce9bc325699cae6cfaec104d1e3477e91d78a5440f8893366cc030c03c36c975`；
`tool_registry.h` = 7662 B / `2a55e68dd54c89f79c3274b222f654e719e8a609d45a5d47c5cb39fb560ec696`。
门：doctest 55/55·450、全引擎 1481/0/3、accept ×2 各 21/21（SUMMARY 打印 6/171）、subset 9888+9889 逐字 6/6、表格 174/174、契约幂等。

## 必核（5 项，全部自己复现）

1. **绕过路径不可用（最重要）**：`MCPToolRegistry::register_tool` 是否**真的**只能经 `ToolBuilder` 触达？
   自己验证三件事：①模块内 `.register_tool(` 的调用点只有 `tool_builder.cpp` 一处（自己 grep）；
   ②**把 `register_tool` 改回 public 后重新编译必须失败**（贴出编译错误；验证后**必须还原**并给出还原证据：文件 sha256 与 `git status`）；③运行期测试确实断言了正向路径仍可注册。
2. **`normalize_project_path`**：折叠 `.`/空/仅空白段，且 **`..` 仍在折叠前被拒绝**。
   自己造 ≥15 条反例（含 `res://a/./../b`、`res://../x`、`res://a//b`、`res:// /`、绝对路径、`res://.`），逐条给结论；
   确认**无项目根之外的逃逸**。特别核实：实现方称 `res://a//b` 由 `-32602` 变为**折叠**（决策者已接受），是否与规范一致。
3. **D-1 落地**：契约 `_meta.order_normative` 为布尔 `false`；`DESIGN-DETAIL` 是否写明「顺序非规范但引擎必须确定性」；
   **确定性 doctest 是否真的能发现问题**——自己构造「两次 `tools/list` 调用」并比较字节（用 9888/9889 实测，两次响应体逐字节相同）。
4. **D-3**：`accept_m1.ps1` 连跑两次，SUMMARY 必须实测打印 `6` 与 `171`，日志中 `{0}`/`{1}` 字面量为 0。
5. **D-5 与生成器**：`gen_table.py` 重渲染两次**逐字节相同**；全部 174 行「按未转义 `|` 切分」恰好 9 列；
   并**独立核实**实现方的说法——HEAD 处 `\|` 转义**早已存在**（`git show HEAD~2:modules/mcp_server/docs/scripts/gen_table.py` 或相应版本），
   即决策者任务书里的 D-5 诊断是否确实过时。（若实现方说法不成立，报缺陷。）

## 另核（简要）

6. 四道工程门自己跑一遍：doctest、全引擎、accept ×2、`check_contract_subset.ps1 -Group project_read_template`。
7. `REPORT-002` 的勘误段是否存在且**未删改原文**；勘误内容（3 vs 1）是否与你自己的复现一致。
8. 观察到的文档不一致（实现方自述「`REPORT-002:194` 仍写『forbids empty segments』与 D-4 后行为不符」）——请核实并判定严重性。

## 约束

只读（唯一例外：第 1 项的变异编译，必须还原并留证）；临时文件放 `%TEMP%\audit003\`；不得 git 写操作；
**绝不占用 9877**（用户正在用的 Godot 4.7.1-mono，PID 36392），测试端口 9888/9889；证据采集用 `curl.exe --data-binary @file`。

## 报告要求

`verdict`（机械/行为/工程门分开判定）、上面 8 项逐条结论与真实输出、`defects`（severity/claim/evidence/location/recommendation）、
`unverifiable`、`risks`、`next_step_recommendation`。**返回值：≤10 行 + 报告路径 + verdict。**