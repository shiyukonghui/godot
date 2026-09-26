# TASK-001 — 命名映射 v1.1（修复审计缺陷）+ 重生成契约与规范文档

> **执行者须知**：你没有参与此前工作，本文件是你的**唯一任务来源**，必须自包含地读完再动手。
> 完成后**必须**把完整报告写到 `modules/mcp_server/docs/reports/REPORT-001-rename-map-v1.1.md`，
> 返回给决策者的内容**只允许**是「简洁总结（≤15 行）+ 报告路径」。

## 0. 背景与当前优先级

用户已裁决：**优先完成 Godot 内置 MCP 模块的工具集成与测试；harness（hof-rs）暂停**
（见 `F:\moonbit-hof-rs\DECISIONS.md` 的 **D43**）。本任务是「按批次移植」的前置：先把
**命名事实源**修对，再生成每批对等门的参照契约。

## 1. 必读（规范性，全部只读）

| 文件 | 作用 |
|---|---|
| `modules/mcp_server/docs/tool-rename-map.json` | **被修复对象**（唯一事实源）。当前 67826 B / sha256 `9f5a57e9201b5f7b0b4929c7562eca3345cc8fa280d63fe1079d4bfae302b91b` |
| `modules/mcp_server/docs/DESIGN-DETAIL.md` | §16 执行顺序、**GDR-16**（命名 lint）、**GDR-17**（合并只在无损时允许）、**GDR-18**（条件写） |
| `modules/mcp_server/docs/TOOL-NAMING.md` | 由映射渲染的规范文档（**本任务需重生成**，不得手改） |
| `F:\moonbit-hof-rs\DECISIONS.md` | **D38**（通道前缀裁决）、**D41**（映射）、**D43**（优先级）、**D45**（本任务的全部修复裁决） |
| `F:\moonbit-hof-rs\tests\fixtures\mcp\tools_list.json` | 旧契约（只读输入），sha256 `8f8051c4c0f8941089f0b21a193cef7c51fa7c41d7e312b1463ea8593f313c54` |
| 独立审计报告 | 结论在 `DECISIONS.md` D45 中已逐条转录（缺陷编号 D-1..D-8） |

## 2. 要做的事（逐条，全部来自 D45 / GDR-17 / GDR-18）

### 2.1 D-1（major）：两个截图工具的 `mutating` 改为 `true`
- `get_editor_screenshot` → `editor_capture_screenshot`、`get_game_screenshot` → `running_game_capture_screenshot`
- 两者 `save_path` 非空时会**真的写 PNG 落盘**（`godot_mcp_gdext/src/commands/editor.rs:327-343` / `:395-402`，schema 允许 `res://`）
- **改 `mutating` 为 `true`**，并在 `reason` 写明「**条件写**：`save_path` 非空即落盘」（GDR-18）

### 2.2 D-2 / D-3（major）：**取消两对合并**，各自保留并给可区分名字
按 GDR-17：有损差异不允许合并。**决策者已指定名字，不得自行更改**：

| 旧名 | 原 `new_name`（v1.0） | **v1.1 最终 `new_name`** | 说明 |
|---|---|---|---|
| `search_in_files` | `project_search_file_contents` | `project_search_file_contents` | 保留：逐行 `{file,line,text}`、上限 50、大小写**不敏感** |
| `find_node_references` | 并入上者（merge） | **`project_find_files_referencing_symbol`** | 独立：按文件聚合 `{file,lines[]}`、上限 100、大小写**敏感** |
| `analyze_signal_flow` | `editor_analyze_signal_flow` | `editor_analyze_signal_flow` | 保留：按节点嵌套、仅持久连接（`flags & 1`）、`node_path` **精确**匹配 |
| `find_signal_connections` | 并入上者（merge） | **`editor_list_signal_connections`** | 独立：扁平 `connections[]`+`count`、收全部连接、`node_path` **子串**匹配、有 `signal_name` 过滤 |

- 两条被取消合并的条目：`disposition` 改 `rename`，**删除 `merge_target`**，`reason` 写明**它们的可区分特性**
  （让只看名字的智能体也能选对）。
- **保留的唯一合并**：`get_editor_performance` → `merge_target = get_performance_monitors`，目标 `new_name` = `editor_get_performance_monitors`；
  `reason` 必须写明「**代价：返回值由平铺改嵌套**」。

### 2.3 D-4 / D-5（minor）：结构补强
- `disposition` 改为**枚举**：`rename | keep | merge_into | unregister_until_implemented | fix_implementation_first`
  （**不再**用 `merge_into:<old_name>` 形式）；合并目标改为独立字段 **`merge_target`**（= 保留方 `old_name`）。
- `convention` 块补齐：`disposition_enum`、`scope_enum`、**条件写条款**（GDR-18），并显式写明
  **`mutating` 的口径**：它含「游戏/编辑器状态副作用」（共 101 条），与 hof-rs `is_mutating`（仅「是否改产物」，
  见 `src/runtime/policy.rs:280`）**不是同一谓词**——**禁止把前者直接灌进 `MUTATING_EXACT`**。
- `verb_closed_set` 中的 `evaluate` 用量为 0：**保留**并加注 `unused_in_v1`（附一句说明）。

### 2.4 D-6 / D-7 / D-8（nit）：三处引文失真修正
- `navigate_to`：reason 里引号内容改为 gd 实际文案（`addons/godot_mcp_rs/mcp_runtime_agent.gd:554`），或去掉引号。
- `get_project_info`：reason 误提 `DirAccess`，改为实际 API（`ProjectSettings` + `EditorInterface.get_base_control().get_size()`）。
- `move_node`：reason 注明实现带可选 `new_name`（重命名副作用）。

### 2.5 重生成下游工件（**必须**，否则文档/契约失效）
1. `modules/mcp_server/scripts/gen_renamed_contract.py`：适配新的 `disposition` 枚举 + `merge_target`；
   重跑生成 `modules/mcp_server/docs/tools_list.renamed.json`，**预期 171 条**（174 − 2 下架 − 1 无损合并），
   打印统计与输出 sha256；脚本须 idempotent。
2. `modules/mcp_server/docs/TOOL-NAMING.md`：**由生成器重渲染，禁止手工编辑**。
   - v1.0 的生成器/模板在 `%TEMP%\namdoc\`（`gen_table.py`、`template.md`、`selfcheck.py` 等）。
     若仍存在：**把它们收进 `modules/mcp_server/docs/scripts/`**（该路径在允许改动范围内），
     更新模板中已变化的章节（§2 表格、§3 易混淆分组、§4 处置清单——3 merge 变 1 merge、
     172→171 与 174→171 的计数、§5 迁移清单、§7 证据块与新指纹），然后重渲染。
   - 若 `%TEMP%\namdoc\` 已不存在：需重写等效生成器（同样落 `docs/scripts/`），
     文档结构与 v1.0 保持一致（章节 1 规范 / 2 对照表 / 3 易混淆消解 / 4 处置清单 / 5 迁移清单 / 6 授权判定重构 / 7 证据）。
   - 文档头部指纹（字节数 / sha256 / 条数）必须与新映射一致。
   - 生成器须**可复跑**且确定性（连续两次渲染逐字节相同）。
3. 一致性自检脚本（`CONSISTENCY`：文档里出现的通道前缀标识符必须全部能回查新映射；`DETERMINISM`）必须仍然 PASS。

## 3. 必须自检并留证（全部真实执行，输出进报告）

1. 映射自检（自己写，不得复用 v1.0 的 `check.py` 结论）：`total==174` 且 `len(tools)==174`；
   `old_name` 集合与旧契约**双向差集为空**；非合并项 `new_name` **全局唯一**；
   `new_name` 匹配 `^(editor|running_game|project|os)_[a-z0-9_]+$`；verb ∈ 闭集（**按最长通道前缀剥离**，`running_game_` 自带下划线）；
   `channel`/`verb` 与名字一致；无 `update_`；`disposition` 取值 ∈ 枚举；合并项 `merge_target` 指向存在的 `old_name`。
2. 计数断言：`disposition` = `rename 164 / fix_implementation_first 7 / merge_into 1 / unregister_until_implemented 2`（合 174）；
   `channel` = `editor 103 / project 45 / running_game 24 / os 2`（若因取消合并不变则须说明）；
   `mutating=true` 由 101 变为 **103**（两个截图工具）。
3. 契约：`tools_list.renamed.json` 条数 **171**；不得出现 3 个下架/合并目标的多余名；两个被取消合并的工具各占一条且名字不同。
4. 构建与测试（贴真实输出与退出码）：
   - `scons platform=windows target=editor tests=yes module_mono_enabled=no -j8`（日志落 `%TEMP%`）
   - `bin\godot.windows.editor.x86_64.console.exe --test --test-case=[MCPServer]*` → 全绿
   - `bin\godot.windows.editor.x86_64.console.exe --test` → **0 failed**（基线 1465，不得回归）
   - `powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\accept_m1.ps1` → **连跑两次**均全过
     （注意：该脚本断言 `tools/list` 与 `tools_list.renamed.json` 逐字相等，契约条数变化后**必须仍然成立**）
5. 文档：`TOOL-NAMING.md` 行数/字节/sha256；表格行数断言；确定性两次渲染同哈希；一致性 `CONSISTENCY`/`DETERMINISM` PASS。

## 4. 硬性约束

- 只允许修改 `code\godot\modules\mcp_server\**`。其它一切（引擎其它目录、`godot_mcp_gdext`、**整个 hof-rs 仓库**）**只读**。
- 用户正在使用的 Godot 4.7.1-mono 占用 **9877**（PID 36392）：**绝不占用、绝不杀/重启**；测试端口用 **9888/9889**；scratch 放 `%TEMP%`。
- 提交到 `feature/mcp-server-module`（英文提交信息，形如 `mcp_server: ... (GDR-17, GDR-18)`），**禁止 push**。
  结束后工作树只应剩既有未跟踪物（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`）。
- 不得伪造任何输出；证据必须是你真实执行的片段。不得安装依赖、不得访问 100.105.152.101:18080。
- 本任务之后会有**另一个全新子代理**做独立验收，因此你必须留下**可复现**的证据（命令 + 输出 + 路径）。

## 5. 报告要求

写到 **`modules/mcp_server/docs/reports/REPORT-001-rename-map-v1.1.md`**，包含：

- `status`、`commits`（sha + 一行说明）
- 逐条处置：D-1..D-8 各自「改了什么 / 证据（file:line 或命令输出）」
- 新指纹：`tool-rename-map.json` / `tools_list.renamed.json` / `TOOL-NAMING.md` 的**字节数与 sha256**
- 计数断言的真实输出（disposition / channel / mutating / 契约条数）
- 构建与测试的真实输出与退出码（doctest、全引擎、accept ×2）
- 文档确定性与一致性检查输出
- `deviations`（与任务书的任何偏离，必须显式列出）、`blockers`、`next_step_recommendation`

**返回给决策者**：≤15 行总结 + 上述报告文件的路径。