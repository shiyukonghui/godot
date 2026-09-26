# TASK-003 — 框架修复与加固（审计 5 缺陷 + 两条机制性建议）

> **执行者须知**：本文件是**唯一任务来源**，自包含。完成后**必须**把完整报告写到
> `modules/mcp_server/docs/reports/REPORT-003-framework-fixes.md`；
> 返回给决策者的内容**只允许**是「简洁总结（≤15 行）+ 报告路径」。
> 本任务**不移植新工具**，只做修复、加固与文档同步。

## 0. 来源

独立验收 **TASK-AUDIT-002** 判定 `pass`，但提出 5 个缺陷（D-1..D-5）与两条机制性建议，
决策者在 `F:\moonbit-hof-rs\DECISIONS.md` **D49** 中逐条裁决。本任务执行这些裁决。

## 1. 要改的东西（逐条）

### 1.1 D-1：`tools/list` 顺序**不是契约语义**
- 在 `docs/tools_list.renamed.json` 的 `_meta` 中增加 `"order_normative": false`
  （做法：改 `scripts/gen_renamed_contract.py` 的 `_meta` 生成处，然后重跑生成器；**不要手改契约**）。
- 在 `docs/DESIGN-DETAIL.md` 写作规范：**顺序非规范**，但引擎必须**确定性**
  （同一次构建内，连续两次 `tools/list` 调用输出**逐字节相同**）。
- 加一条 doctest：连续两次 `tools/list` 的响应体**逐字节相等**（证明确定性）。
- **不要**为了对齐契约顺序而重排注册（顺序不是契约）。

### 1.2 D-3：`accept_m1.ps1` 的 SUMMARY 打印字面 `{0}/{1}`
- 位置：`modules/mcp_server/scripts/accept_m1.ps1:1046-1048` 附近。
- 原因：字符串拼接与 `-f` 的优先级 → 用**括号**把拼接结果包起来再格式化。
- 修后**实测**：SUMMARY 必须打印 `implemented tools = 6` 与 `contract = 171`（不得再出现 `{0}`/`{1}`）。

### 1.3 D-4：`normalize_project_path` 不折叠 `.` 段
- 现状：`res://.`、`res://src/.`、`res:// `（单空格）都能打开目录且 `path` 原样回显。无安全影响，但要归一。
- 改为：折叠 `.` 段与空段（含仅空白段），并保持现有安全约束（只允许 `res://`、禁 `..` 逃逸）。
- 加 doctest：`res://.` → `res://`；`res://src/.` → `res://src`；`res:// ` → `res://`
  （注意：**不要**因此放宽 `..` 的拒绝）。

### 1.4 D-5：`TOOL-NAMING.md` 有一行 reason 含未转义 `|`
- 位置：生成器 `docs/scripts/gen_table.py`（渲染 markdown 表格单元格）。
- 改为：渲染前把单元格内的 `|` 转义为 `\|`；重渲染 `docs/TOOL-NAMING.md`。
- 断言：**全部 174 行**按 `|` 切分都得**恰好 9 列**（现在只有 173 行满足）。

### 1.5 D-2：实现方报告的叙述错误（**只改文档**）
- `docs/reports/REPORT-002-b1-framework.md` 中「同一输入 3 vs 0 命中」的实例**不成立**，实测为 **3 vs 1**
  （机制与结论仍成立）。在该报告**末尾追加「勘误」段**（保留原文，不要删改原句），
  写明：审计方 TASK-AUDIT-002 复现为 `FOOBAR` → `project_search_file_contents` 3 命中 /
  `project_find_files_referencing_symbol` 1 命中；原叙述「0 命中」有误。

### 1.6 机制性建议①：`MCPToolRegistry::register_tool` 必须**不可绕过**
- 现状：`register_tool` 为 public，可绕过 `ToolBuilder` 的命名 lint（GDR-16）、`mutating` 声明（GDR-18）
  与编辑器守卫（GDR-19 §17.3）。
- 改为：**唯一注册路径是 `ToolBuilder`**（可私有化并 friend，或等价机制）。
- **必须有一条测试**证明绕过路径不可用（编译期拒绝或运行期断言，任选其一，但要能自动验证）——
  不要只写「已私有化」就算完成，要贴出证明。
- 在 `docs/DESIGN-DETAIL.md` §17.2 写明「所有组必须经 `ToolBuilder` 注册」。

### 1.7 机制性建议②：并行/串行纪律写入文档
- 在 `docs/DESIGN-DETAIL.md` §17.1 写明：`tools/registration.cpp` 是**所有组共写的同一处**，
  经验证（`git merge-file` 模拟两代理各加一行 → 4 处冲突）**必然冲突**；
  因此**一批只有一个实现者在改树**，注册行由该批实现者单独追加。

## 2. 门（自己跑并贴真实输出）

1. `--headless --test --test-case="[MCPServer]*"` → 全绿（基线 53/53·410 断言，允许因新测试增加）。
2. 全引擎 `--headless --test` → **0 failed**（基线 1479 passed / 3 skipped，只允许因新测试增加）。
3. `scripts/accept_m1.ps1` **连跑两次** → 全过，且 SUMMARY 打印 `6` 与 `171`。
4. `scripts/check_contract_subset.ps1 -Group project_read_template` → 9888 与 9889 逐字 6/6。
5. `docs/scripts/gen_table.py` 重渲染后：全部 174 行**恰好 9 列**；文档确定性（两次渲染逐字节相同）；
   头部指纹与新契约一致。
6. `scripts/gen_renamed_contract.py` 重跑幂等，且 `_meta.order_normative == false`；契约仍 **171 条**。

## 3. 硬性约束

- 只允许修改 `code\godot\modules\mcp_server\**`。其它一切（引擎其它目录、`godot_mcp_gdext`、**整个 hof-rs 仓库**）**只读**。
- 用户正在使用的 Godot 4.7.1-mono 占用 **9877**（PID 36392）：**绝不占用、绝不杀/重启**；测试端口 **9888/9889**；scratch 放 `%TEMP%`。
- 证据采集一律用 `curl.exe --data-binary @file`（JSON body 作为 Windows 命令行参数会丢引号）。
- 提交到 `feature/mcp-server-module`（英文提交信息），**禁止 push**；结束后工作树只应剩既有未跟踪物
  （`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`）。
- 不得伪造输出；之后会有**全新子代理**做独立验收（TASK-AUDIT-003），证据必须可复现。
- 不得安装依赖、不得访问 100.105.152.101:18080。

## 4. 报告要求（`docs/reports/REPORT-003-framework-fixes.md`）

- `status`、`commits`（sha + 一行说明）
- 逐条处置：D-1..D-5 + 建议①②，各自「改了什么 / 证据（file:line 或命令输出）」
- 门：上面 6 项的真实输出与退出码
- 新指纹：`tools_list.renamed.json`、`TOOL-NAMING.md`、脚本（若动过）的字节数与 sha256
- `deviations`、`blockers`、`next_step_recommendation`

**返回给决策者**：≤15 行总结 + 报告路径。