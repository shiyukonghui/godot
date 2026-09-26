# TASK-AUDIT-001 — 独立验收：命名映射 v1.1 + 重生成的契约与规范文档

> **执行者须知**：你是**独立验收方**，没有参与实现，**不得采信实现方与决策者的任何结论**——
> 只依据需求、设计、代码与你自己可复现的证据。上一轮（v1.0）验收判了 `fail` 并找出 3 类真实缺陷，
> 本轮要核实这些缺陷**是否真的闭合**，以及**是否引入了新缺陷**。
>
> 完成后**必须**把完整报告写到 `modules/mcp_server/docs/reports/REPORT-AUDIT-001-rename-map-v1.1.md`，
> 返回给决策者的内容**只允许**是「简洁总结（≤15 行）+ 报告路径 + verdict」。

## 1. 验收对象（当前实测指纹，请自行重算核对）

| 对象 | 路径 | 实现方声称 |
|---|---|---|
| 命名映射 v1.1 | `modules/mcp_server/docs/tool-rename-map.json` | 70917 B，sha256 `2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd` |
| 期望契约 | `modules/mcp_server/docs/tools_list.renamed.json` | 95060 B，sha256 `96495badd5abe5670aa075ffe086c3287e7b590fefffdd1d05fdaab974bd50ab`，**171** 条 |
| 规范文档 | `modules/mcp_server/docs/TOOL-NAMING.md` | 98381 B，sha256 `078b94e546895e8144c75b6aab4ad1be327a706f3c01c382f8f4272d43466631`，869 行 |
| 生成器/自检 | `modules/mcp_server/docs/scripts/{check_rename_map.py,gen_table.py,selfcheck.py,template.md}` | 已落库 |
| 契约生成器 | `modules/mcp_server/scripts/gen_renamed_contract.py` | 已适配 v1.1 |

## 2. 规范依据（只读）

- `modules/mcp_server/docs/DESIGN-DETAIL.md`：**§16**（执行顺序）、**GDR-16**（命名 lint）、**GDR-17**（合并只在无损时允许）、**GDR-18**（条件写）
- `modules/mcp_server/docs/tasks/TASK-001-rename-map-v1.1.md`（实现方执行的任务书）
- `F:\moonbit-hof-rs\DECISIONS.md`：**D38 / D41 / D43 / D45**（D45 是本轮要闭合的裁决清单）
- 旧契约（只读）：`F:\moonbit-hof-rs\tests\fixtures\mcp\tools_list.json`，sha256 `8f8051c4c0f8941089f0b21a193cef7c51fa7c41d7e312b1463ea8593f313c54`

## 3. 必须核实的内容

### 3.1 上一轮缺陷是否闭合（逐条给「已闭合 / 未闭合 / 部分闭合」+ 证据）
- **D-1**：`editor_capture_screenshot`、`running_game_capture_screenshot` 的 `mutating` 是否为 `true`，
  且 `reason` 写明「条件写：`save_path` 非空即落盘」；`convention` 是否有条件写条款（GDR-18）。
  **并自行读实现**确认「`save_path` 非空即写 PNG」这一事实是否成立（`editor.rs:327-343` / `:395-402`）——
  如果事实相反，那么本次改动方向就是错的，必须报缺陷。
- **D-2 / D-3**：两对合并是否已取消（3 条 merge 变 1 条）；
  `find_node_references` → `project_find_files_referencing_symbol`、`find_signal_connections` → `editor_list_signal_connections`
  是否各自独立成条且名字不同；两条 `reason` 是否写明**可区分特性**（输出形状 / 上限 / 大小写 / 连接过滤 / 路径匹配）。
- **D-4**：`disposition` 是否为枚举（不再有 `merge_into:<old>` 形式）；合并目标是否走独立字段 `merge_target`
  且指向真实存在的 `old_name`。
- **D-5**：`convention` 是否补齐 `disposition_enum`、`scope_enum`、条件写条款，以及
  **`mutating` 口径说明**（与 hof-rs `is_mutating` 不是同一谓词、禁止直接灌进 `MUTATING_EXACT`）。
- **D-6 / D-7 / D-8**：三处引文失真是否已改（`navigate_to` 的 gd 文案、`get_project_info` 的 `DirAccess`、`move_node` 的 `new_name`）。
  **逐条读源码确认新引文与实现一致**。

### 3.2 机械层重算（自写脚本，**不得**复用 `docs/scripts/check_rename_map.py` 的结论）
- 字节数 / sha256 / 条数 / 字段完整性；`old_name` 与旧契约**双向差集为空**；
- `new_name` 正则、verb 闭集（**最长通道前缀剥离**）、`channel`/`verb` 与名字一致、无 `update_`、非合并项名字唯一；
- 计数独立重算：`disposition`、`channel`、`scope`、`mutating`（实现方声称 `rename 164 / fix 7 / merge 1 / unregister 2`、
  通道 `103/45/24/2`、`mutating=true` **103**）——全部自行复算比对。

### 3.3 契约与文档
- `tools_list.renamed.json`：条数是否 **171**；是否**不含** 2 个下架项与 1 个合并目标；
  是否**含**两个被取消合并的新名各一条；`name` 是否与映射一一对应；`description`/`inputSchema` 是否确实来自旧契约（抽样比对）；
  `_meta` 是否自洽。
- 契约生成器是否 **idempotent**（你自己跑两次比 sha）。
- `TOOL-NAMING.md`：174 行表格**逐字段**与映射对账（上一轮做了 174/174，本轮同样要求 0 不一致）；
  文档头部指纹是否与新映射一致；**确定性**（连续两次渲染逐字节相同）；
  文档内是否有残留的 v1.0 事实（例如「3 对合并」「169」「2 个下架」表述矛盾、`editor_fill_tilemap_rect` 之类的旧名、
  已取消合并的名字被当作合并目标）。

### 3.4 反例工作（对抗性，必做）
- 重新给出**新名字里最容易被智能体弄混的 Top 5 配对**（v1.1 后应重新评估：上一轮的第 1 名是
  `project_convert_uid_to_path` ↔ `project_convert_path_to_uid`，请核实是否仍然存在、以及取消合并后是否产生了新的危险配对）。
- **检查取消合并是否引入新混淆**：`project_search_file_names` / `project_search_file_contents` / `project_find_files_referencing_symbol`
  三者，以及 `editor_analyze_signal_flow` / `editor_list_signal_connections` 两者，一名只看名字的智能体能否选对？给出你的判断。
- 抽样 ≥12 条对回实现源码（跨 4 个通道、覆盖 7 个 fix 与 2 个 unregister 中的若干）。

### 3.5 工程门（自己跑，不采信转述）
- `--test --test-case=[MCPServer]*` 与全引擎 `--test`（声称 39/39 与 1465/1465，0 failed）；
- `modules/mcp_server/scripts/accept_m1.ps1` **连跑两次**。
- **特别核实实现方自报的一条偏差**：该脚本的「逐字对等门」实际只比较 `tools_list.renamed.json` 中
  **已实现的 2 个工具**（`$ToolNames`），**并非整个 171 条契约**。请确认这个描述是否准确；
  若不是，给出真实范围；若是，请判断「把 171 条全量逐字比较」应该属于哪个阶段的门（并给出建议）。

## 4. 硬性约束

- **不得修改任何文件**（被验收件、脚本、文档全部只读）；临时脚本与输出放 `%TEMP%\audit001\**`。
- 不得 git 写操作；不得安装依赖；不得占用 **9877**（用户正在用的 Godot 4.7.1-mono，PID 36392）；测试端口 9888/9889。
- 所有结论必须附**你真实执行**的命令输出或源码行号；严格区分「证据支持」与「推断」；不确定写 `unconfirmed`。

## 5. 报告要求

写到 `modules/mcp_server/docs/reports/REPORT-AUDIT-001-rename-map-v1.1.md`：

- `verdict`: `pass` | `fail`（**机械层与数据层分开判定**，若仅剩 nit 可 pass 但必须列出）
- 上一轮 D-1..D-8 的**逐条闭合结论**（含你独立读码的复核）
- `criteria`：本次核实的各项（id / 结论 / 方法 / 证据）
- `top_confusable_pairs`：Top 5 + 选错机制
- `defects`：新发现的缺陷（severity / claim / evidence / location / recommendation）
- `unverifiable`、`risks`、`next_step_recommendation`

**返回给决策者**：≤15 行总结 + 报告路径 + `verdict`。