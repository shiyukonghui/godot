# TASK-075 — 修第 5 轮确认项：**D2 契约违约+静默** / **补读工具** / **D9 计数** / D4·D5 最小复现 / 分析器漏报

> 先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册）与本文件。
> 来源：`PLATFORMER-FINDINGS.md`（D1…D11、十一条判据、汇总者的两条「最该先做」）。报告（**绝对路径**）
> `...\modules\mcp_server\docs\reports\REPORT-075-round5-fixes.md`。契约 **176 → 177**（新增 1 个读工具）。

## 1. **D2（S1，最高优先）**：脚本写族**静默丢弃** + **契约承诺的 `readable` 字段根本不存在**

实测：`editor_set_node_script(_batch)` 在**根类型 ↔ `extends` 兼容**时才生效；不兼容时回 **`attached:true`**，
而引擎**静默丢弃**（编辑器日志 `Area2D` 0 次 / 游戏 30 次）；且契约明文承诺逐节点报「script was readable」，
**响应全文没有该字段**（sha `ef8db75df33ab89b`）。
**要求**：
1. **先复现**（给出最小复现：一个合法绑定 + 一个不兼容绑定，两者响应逐字对照）。
2. **实现契约已承诺的语义**：逐节点真的回答 `readable`（读回核实），**不兼容必须如实失败**
   （合适的错误码 + `data.suggestion`，**不得** `attached:true` 而引擎已丢弃）。
3. **合法绑定对照必须存在**（防假修复）：合法绑定仍 `attached:true` + `readable:true`。
4. **不得**按已被证伪的 D1（「批量挂脚本不落盘」，已被 §C 三路证据推翻）开工。

## 2. **新增 `project_read_text_file`**（对称消除「有写无读」）

走 `ADDED_TOOLS`（**契约 177 = 171 + 6**）：
- 名 `project_read_text_file`（`project` + `read` + `text_file`；作用域 `project`，`mutating=false`）。
- **描述（英文，逐字）**：`Read a text file inside the project and answer its bytes, size and digest, so a file written by a tool can be verified with a tool.`
- **`inputSchema`**：`path`（string，必填）、`max_bytes`（integer，可选，默认 1 MiB，上限如 16 MiB）。
- **行为**：**只读**；**限制在 `res://` 内**（拒绝越界、`..`、绝对路径、只给目录）；返回 `path`/`size`/`sha256`/`text`
  （或 `text_omitted:true` + 原因，当超过 `max_bytes`）；**如实声明不解析语义**（不判断它是 JSON/配置/场景）；
  非 UTF-8 或缺文件 → 明确错误码 + `data.suggestion`。
- **证据**：①用 `project_write_text_file` 写一份 → 用新工具读回 → **sha 逐字等于写时回执与磁盘值**（三处一致）；
  ②四类拒绝（越界 / `..` / 绝对路径 / 目录）各一条；③`max_bytes` 触发 `text_omitted` 的对照。

## 3. **D9**：错误计数低估（游戏侧非 ok 实为 **14**，A/B 都记 2）

**要求**：查明**计数从哪来**（`文件:行`），给出**为什么漏**（例如只统计 HTTP 层而非 JSON-RPC `error`、或只统计某一类），
修正后给**修复前后对照**（同一份追踪上 2 vs 14）；**不得**只改数字而不改根因。

## 4. **D4 / D5：先最小复现，再决定修法**

- **D4**：**实例子场景内部节点**在编辑器侧不可寻址（属性写工具到得了 `Anim`；**信号工具与 `editor_get_scene_tree` 都到不了**），运行期正常。
  **最小复现**：一个主场景 + 一个被实例化 ≥1 次的子场景 → 列出三种工具在同一路径上的结果差异。**结论二选一**：
  修（统一寻址）或**如实声明边界**（说明哪种工具支持、哪种不支持、调用方如何绕）。
- **D5**：TileSet 无 atlas source → tile 写入不可达；终态 `has_tile_set:false`。**最小复现**后**定性**（是能力缺口还是缺陷）。

## 5. **分析器结构性漏报**（S3，但属「诊断工具自己瞎」家族，优先）

`analyze_mcp_trace.py` 因 **`args` 恒为 `str`** 而漏报一整类信号。**要求**：查明（`文件:行`）→ 修 →
给**修复前后在同一份追踪上的对照**（漏报的类别真的出现了）→ **并加仓库内断言**（防复发）。

## 6. 门与纪律

第 0 步 `scripts/build_local.cmd -Force`（tests=yes，**从 cmd 启动**）+ `--version == HEAD`；五道门 + 门⑥ 三段式 +
`--check-completeness/--added/--generator-version`（**177 = 171+6**）+ `accept_m1` ×2（清单一致）+ `check_exit_propagation.py`
+ `check_tautologies.py` + **`check_engine_anchor.ps1`**；回归相关脚本**逐条归因**；**构建严格串行**；
**绝不占用/杀/重启 9877**；端口 9888/9889；禁止 push；`.ps1` 纯 ASCII；**红相位输出当场保存**；结论按 D86 标锚点；产物**绝对路径**。