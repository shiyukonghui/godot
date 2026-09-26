# TASK-043 — 描述诚实化：把「整文件重写」写进受影响的工具描述（override）

> 执行者须知：先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册），再读本文件。
> 报告写到 `docs/reports/REPORT-043-rewrite-honesty-descriptions.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 决策者裁决（背景）

TASK-042 §2 **实测**：凡经引擎写出口保存 `project.godot` 的操作（`project_set_setting` 家族、以及 M-6 之后的
`editor_add_input_action`）都会**整文件重写** —— **手写注释全部丢失**、引擎写入自己的固定 7 行头、
其余行逐字保留、幂等；**引擎无局部发布 API**（`project_settings.cpp:1162-1210 / 1234-1341`，`ConfigFile::save` 同样整文件）。
拼接方案（只追加 `[input]` 条目）已被 spike 证明可行，但**本批不实现**（它会绕过引擎写出口，风险面另议）。

**裁决**：**副作用不得沉默** → 把该事实写进**受影响的每个工具的描述**（`DESCRIPTION_OVERRIDES`，**只在句尾 append**），
让调用方**在调用前**就知道「这会重写整个 `project.godot` 并丢失手写注释」。

## 1. 要做的事

1. **先普查**：**逐个确认**哪些工具真的会经引擎写出口保存 `project.godot`（读源码，**不要**靠猜；
   列出工具名 + 源码行 + 写出口调用链）。**只对确认的**加描述。
2. **描述措辞**（英文，与既有描述风格一致，语义要点）：
   ①该调用会**重写整个 `project.godot`**；②**手写注释会丢失**；③其余设置逐字保留、幂等；
   ④若调用方需要保注释，**自行备份**。**不要**加参数、**不要**承诺做不到的事。
3. **走 `DESCRIPTION_OVERRIDES`**（`mode=append`）+ `GENERATOR_VERSION` 递增 + **重生成契约** + **更新全部指纹**
   （契约 sha、`_meta.overrides` 条数、`_meta.map_sha256` 若受影响、组清单若有引用）；
   **不得手改契约文件**。门① 逐字通过。
4. **行为不变**：本批**不改任何实现代码**（只改描述与生成器）；给出「实现文件 diff 为空」的证据。
5. **线上核实**：从 9888 抓 `tools/list`，确认被改工具的描述**含有**新句子（且与契约逐字相等）。

## 2. 门

- 第 0 步：`scripts/build_local.cmd -Force`（`tests=yes`）重建 + 校验 `--version` == HEAD（**从 cmd 启动**）。
- 五道门 + 门⑥ 三段式；**门① 逐字通过**（含被改工具）。
- 回归：重跑 `mcp042`（30/30）、`mcp041`（32/32）、`mcp040` 两脚本、`mcp032/033/034/035/036`、`probe037`、门⑤ ×2。

## 3. 报告

按手册 §4，写到 `docs/reports/REPORT-043-rewrite-honesty-descriptions.md`；另加：
「受影响工具的**普查表**（工具/源码行/写出口链）」「override 记录（old_name/mode/reason）」
「契约 diff（结构化，证明只动这些描述 + `_meta`）」「线上核实」「结论锚点（D86）」。
**返回值：≤15 行总结 + 报告路径。**