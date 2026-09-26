# B0 BRIEF — 命名 lint 闸门 + 重命名后的期望契约（冻结任务书）

| 项 | 值 |
|---|---|
| 任务 | **B0**（GDR-16 落地的第一步，DESIGN-DETAIL §16 第 1、2 项 + 第一次真实改名） |
| 引擎仓库 | `F:\RustProjects\godot-mcp-pro\code\godot`（分支 `feature/mcp-server-module`，**禁止 push**） |
| 唯一允许写入的路径 | `modules/mcp_server/**`（本模块目录） |
| 规范源 | `docs/DESIGN-DETAIL.md` §16 / GDR-16 / §7 / §9 / §10；`docs/TOOL-NAMING.md` §1.5（L1–L6）；`docs/tool-rename-map.json`（174 条，唯一事实源） |
| 旧契约（只读输入） | `F:\moonbit-hof-rs\tests\fixtures\mcp\tools_list.json`，sha256 `8f8051c4c0f8941089f0b21a193cef7c51fa7c41d7e312b1463ea8593f313c54` |

## 0. 只读红线与环境

- **只允许**修改 `modules/mcp_server/**`。引擎其它目录、`godot_mcp_gdext`、整个 `F:\moonbit-hof-rs` **只读**。
- 用户正在使用的编辑器占用 **9877（PID 36392）**：绝不占用、绝不杀、绝不重启。
  模块自测端口固定 **9888 / 9889**（`accept_m1.ps1` 已如此）；scratch 一律放 `%TEMP%`。
- 构建：`cd F:\RustProjects\godot-mcp-pro\code\godot` 后
  `cmd /c "D:\Anaconda\Scripts\scons.exe platform=windows target=editor tests=yes module_mono_enabled=no -j8 > %TEMP%\b0-build.log 2>&1"`
- 测试**必须用 `cmd /c` 跑**以便取到可靠退出码（PowerShell 会把 stderr 当错误、把退出码变成 1）：
  - `cmd /c "bin\godot.windows.editor.x86_64.console.exe --test --test-case=""[MCPServer]*"" > %TEMP%\b0-test-mcp.log 2>&1 & echo EXIT=%ERRORLEVEL%"`
  - `cmd /c "bin\godot.windows.editor.x86_64.console.exe --test > %TEMP%\b0-test-all.log 2>&1 & echo EXIT=%ERRORLEVEL%"`
- 测试模式下的 `ERROR: [MCP] SceneTree never became available` 是**既有噪声**，不是失败。
- 基线（本任务书作者实测）：`--test-case=[MCPServer]*` = **33 cases / 204 assertions / 0 failed / 1429 skipped**，退出码 0。

## 1. 命名 lint（GDR-16）——注册期强制

### 1.1 解析算法（必须按最长前缀剥离）

通道前缀按**字符长度降序**尝试：`running_game_`(13) → `project_`(8) → `editor_`(7) → `os_`(3)。
**绝不能用 `split('_')[1]`**：`running_game_get_scene_tree` → 动词必须是 `get`，不是 `game`。

`tool_registry.h` 的 `MCPToolDef` 增加两个显式字段（`String`）：

```cpp
struct MCPToolDef {
	StringName name;
	// GDR-16: explicit naming metadata; both must agree with `name`.
	String channel;   // editor | running_game | project | os
	String verb;      // member of the closed verb set
	String description;
	Dictionary input_schema;
	MCPToolScope scope = MCPToolScope::BOTH;
	Variant (*handler)(const Dictionary &p_args, String &r_error) = nullptr;
};
```

`MCPToolRegistry` 公开两个静态谓词（供单测直接断言解析结果）：

```cpp
	// GDR-16 L1: `<channel>_<verb>_<object>[_<qualifier>]`, channel stripped by
	// longest prefix. Returns false when no channel prefix matches or when the
	// remainder is empty / contains a character outside [a-z0-9_].
	static bool parse_tool_name(const String &p_name, String &r_channel, String &r_verb);
	// GDR-16 L1..L4 plus the declared-metadata cross check. On failure it fills
	// `r_error` with an ASCII reason and returns false.
	static bool validate_tool_name(const String &p_name, const String &p_declared_channel, const String &p_declared_verb, String &r_error);
```

`register_tool` 返回值由 `void` 改为 **`bool`**（既有调用点全部忽略返回值，不需要改调用点）：

```cpp
bool MCPToolRegistry::register_tool(const MCPToolDef &p_def) {
	String reason;
	if (!validate_tool_name(String(p_def.name), p_def.channel, p_def.verb, reason)) {
		ERR_PRINT(reason);
		return false;
	}
	if (!tools.has(p_def.name)) {
		order.push_back(p_def.name);
	}
	tools[p_def.name] = p_def;
	return true;
}
```

不合规 = **不进入注册表**（于是永不出现在 `tools/list`），并打印明确原因。

### 1.2 校验顺序与错误文案（**顺序是规范的一部分**，测试按子串断言）

1. 空名 → `MCPToolRegistry: refusing to register a tool without a name (GDR-16 L1).`
2. **含 `update_`** → `MCPToolRegistry: tool name '%s' contains the banned verb 'update_' (GDR-16 L4).`
   （必须排在 L2 之前：`editor_update_node_property` 的通道与声明都合法，只有 L4 能独立命中它。）
3. L1 解析失败 → `MCPToolRegistry: tool name '%s' must match ^(editor|running_game|project|os)_[a-z0-9_]+$ (GDR-16 L1).`
4. L2 动词不在闭集 → `MCPToolRegistry: tool name '%s' has verb '%s', which is not in the closed verb set (GDR-16 L2).`
5. L3 声明通道与名字不符 → `... declares channel '%s' but the name says '%s' (GDR-16 L3).`
6. L3 声明动词与名字不符 → `... declares verb '%s' but the name says '%s' (GDR-16 L3).`

**全部为 ASCII**（避免测试断言受编码影响）。`channel`/`verb` 未声明（空串）一律按 L3 不符处理。

闭集（37 个，与 `docs/tool-rename-map.json` 的 `convention.verb_closed_set` 逐字一致，硬编码在 `tool_registry.cpp`）：
`get list read find search create add remove delete set edit rename reparent move duplicate connect disconnect play stop run execute evaluate capture assert validate simulate export deploy reload rescan bake open save setup analyze detect convert`

**名字长度不设上限**（不得加任何长度检查）。

**明确不做**（不发明需求）：不要求 `_<object>` 段存在（L1 的正则允许 `editor_get`）；不引入 `mutating` 字段（L6 属后续批次）。

### 1.3 单测（追加在 `tests/test_mcp_server.h`，标题一律以 `[MCPServer]` 开头）

| # | 测试用例标题 | 覆盖 |
|---|---|---|
| A | `[MCPServer] naming lint accepts compliant names across all four channels` | ① 合规名通过 + `err.is_empty()` + 注册成功（四通道各一例，含 `project_get_info`） |
| B | `[MCPServer] naming lint rejects an unknown channel prefix` | ② `game_get_x` 失败（断言含 `GDR-16 L1`）、未入表、`get_visible_tool_count` 不变；另加 `Editor_get_info`（大写） |
| C | `[MCPServer] naming lint rejects a verb outside the closed set` | ③ `editor_navigate_to_node`、`editor_clear_output_panel` 失败（断言含 `GDR-16 L2`） |
| D | `[MCPServer] naming lint bans update_ anywhere in the name` | ④ `editor_update_node_property`（声明 channel=`editor`、verb=`set`，通道与动词都合法）失败，断言含 `GDR-16 L4` **且**含 `update_` |
| E | `[MCPServer] naming lint rejects a declared channel or verb that disagrees with the name` | ⑤ `editor_get_node_properties`+声明 `project`；`project_get_settings`+声明 verb `list`；`project_get_info`+空 verb |
| F | `[MCPServer] naming lint strips running_game_ by longest prefix` | ⑥ 直接断言 `parse_tool_name("running_game_get_scene_tree")` → channel `running_game`、verb `get`（且 `verb != "game"`）；四通道解析；注册后 `is_tool_visible(name, false)` 为真 |

B/C/D/E 还必须断言 `CHECK_FALSE(registry.has_tool(<bad name>))`。

既有测试的适配（否则 lint 一上线就红）：

- `tests/test_mcp_server.cpp` 的 `_register_scope_tool` 增加 `p_channel`/`p_verb` 形参并写入 `def.channel` / `def.verb`；
  `build_scope_registry` 的三个探针名改为合规名：`editor_get_scope_probe`(EDITOR/`editor`/`get`)、
  `running_game_get_scope_probe`(GAME/`running_game`/`get`)、`project_get_scope_probe`(BOTH/`project`/`get`)。
- `tests/test_mcp_server.h` 中 `editor_only` / `game_only` / `both_tool` 的全部引用（含 `is_tool_visible`、
  `tools/list` 顺序断言）同步替换；`tools/list` 顺序仍为插入序。

## 2. `docs/tools_list.renamed.json`——重命名后的期望契约

生成脚本：**`modules/mcp_server/scripts/gen_renamed_contract.py`**（Python 3.9 标准库，不用第三方包）。

- 入参（带默认值，可被 CLI 覆盖）：`--old-contract`（默认绝对路径 `F:\moonbit-hof-rs\tests\fixtures\mcp\tools_list.json`）、
  `--map`（默认 `docs/tool-rename-map.json`，相对脚本自身定位）、`--out`（默认 `docs/tools_list.renamed.json`）。
- 变换：`name` ← 映射里的 `new_name`；`description` 与 `inputSchema` **原对象原样搬运**（脚本内断言重序列化后逐字相同）；
  顶层 `id` / `jsonrpc` 沿用旧契约；`result.tools[]` 顺序 = 旧契约顺序。
- **剔除**：`disposition == "unregister_until_implemented"`（2 条）不产出。
- **merge 去重**：`disposition == "merge_into:<keep>"`（3 条）不产出；`<keep>` 是**保留方的 `old_name`**
  （已核对：`get_performance_monitors` / `analyze_signal_flow` / `search_in_files`，三者都命中其它条目的 `old_name`）。
- **保留** `fix_implementation_first`（7 条，将来要注册）。
- 顶层加 `_meta`：`generated_from`、`generated_from_sha256`、`map_path`、`map_sha256`、`tool_count_in`(174)、
  `count`(169)、`excluded`(2 个 old_name)、`merged`(3 个 `{old_name,new_name,merged_into}`)、`generator_version`、`generated_by`。
- **显式覆盖钩子**：脚本内定义空的 `DESCRIPTION_OVERRIDES = {}` / `SCHEMA_OVERRIDES = {}`（值为含 `reason` 的记录），
  非空时必须写进 `_meta.overrides`；**没有显式清单就不得改动 description/inputSchema 的任何一个字**。
- **自带自检（失败即非零退出）**：
  1. 映射条数 == `total` == 174，且映射 `old_name` 集合与旧契约 `name` 集合**完全相等**（双向差集为空）；
  2. 除被剔除者外，每条 `new_name` 都用与 §1.1 **同构**的 Python 谓词校验：L1 正则、最长前缀剥离、
     verb ∈ `convention.verb_closed_set`、`verb == entry.verb`、`channel == entry.channel`、不含 `update_`；
  3. 输出 169 条、`new_name` **互不重复**；剔除计数恰为 merge 3 / unregister 2；
  4. 每条被合并项与保留方的新名一致（即去重后不产生重名）。
- **统计打印（ASCII）**：输入 174 → 输出 169、merge 3、unregister 2、旧契约 sha256、映射 sha256、输出 sha256。
- **idempotent**：同输入同输出（跑两次 sha256 相同）；UTF-8 **无 BOM**、`ensure_ascii=False`、LF、末尾换行。

## 3. 把 M1 的 2 个工具改到新名

- `tools/project.cpp`：`name` → `project_get_info` / `project_get_settings`（**以映射表为准**），
  并补齐 `channel = "project"`、`verb = "get"`（在 lint 落地的那一步必须同时给出，否则这两个工具会被闸门拒掉）。
- `tools/project.h` 顶部注释同步；`mcp_server.cpp` 的 `registry.has_tool("get_project_info")` 幂等守卫 → `project_get_info`。
- `tests/test_mcp_server.h`：全部旧名引用（`tools/call` 的 `params.name`、`call_tool` 实参、
  规范化 `tools/list` 期望串里的 `"name"`、测试标题）。
- `scripts/accept_m1.ps1`：
  - `$ToolNames` → `@('project_get_info','project_get_settings')`；
  - 参照契约 `$Fixture` → **`$RenamedContract = Join-Path $RepoRoot 'modules\mcp_server\docs\tools_list.renamed.json'`**
    （§16 第 2 项明确把它定为**每批对等门的参照物**；description/inputSchema 由旧契约机械搬运，对等语义不变），
    同步改 `Compare-ToolListToFixture` 里的读取与过滤，并加一条**文件缺失时明确报错 exit 2** 的守卫；
  - case 4 / case 6 的 `"name":"get_project_info"` → `"name":"project_get_info"`；
  - 头部注释补一句参照物来源（旧 fixture + 生成脚本）。
  - 端口纪律与「只杀自己启动的 PID」**一个字都不许动**。

## 4. 实施顺序（TDD，红-绿必须贴原生输出）

| 步 | 动作 | 期望 |
|---|---|---|
| S0 | **RED-0**：先把改名后的期望写进测试（§3 的 `tests/**` 部分） | 构建通过，`--test-case=[MCPServer]*` **原生红**：`tools/list exposes exactly the two ported tools` 等因仍是旧名而失败 |
| S1 | **GREEN-0**：`project.cpp` / `mcp_server.cpp` 改名（此步不设 `channel`/`verb`，注册表仍是宽松的） | 33 cases 全绿 |
| S2 | **RED-1**：加 `channel`/`verb` 字段 + `parse_tool_name`/`validate_tool_name` 声明 + **宽松占位实现**（`validate` 恒 true、`parse` 恒 false，标注 `// TDD RED placeholder`）+ 单测 A–F + 探针名适配 | 构建通过，A 通过、**B/C/D/E/F 原生断言失败**（是 `CHECK_FALSE` 失败，**不是编译错误**） |
| S3 | **GREEN-1**：实现真解析/真校验 + `register_tool` 闸门 + `project.cpp` 补 `channel`/`verb` | 39 cases 全绿（33+6） |
| S4 | 契约生成器 + 生成契约 + 跑两次比对 sha256 | 169 条，自检全过，idempotent |
| S5 | `accept_m1.ps1` 改造 | — |
| S6 | 提交（下面 4 个 commit） | 工作树只剩既有未跟踪物 |
| S7 | 终局门：构建 → MCP 单测 → 全引擎 `--test` → `accept_m1.ps1` **连跑两次** | MCP 39/39 绿；全引擎 **0 failed**（基线 1462 cases）；accept **20/20 + 退出码 0**，两次一致 |

**提交（英文信息，禁止 push；必须按路径 `git add`，禁止 `git add -A` / `git add .` / `git commit -a`）**：

1. `mcp_server: rename the two M1 tools to the project_ channel (GDR-16)`
   → `modules/mcp_server/tools/project.h`、`tools/project.cpp`、`mcp_server.cpp`、`tests/test_mcp_server.h`
2. `mcp_server: generate docs/tools_list.renamed.json from the rename map (GDR-16)`
   → `modules/mcp_server/scripts/gen_renamed_contract.py`、`docs/tools_list.renamed.json`
3. `mcp_server: enforce the naming lint at registration (GDR-16)`
   → `modules/mcp_server/tool_registry.h`、`tool_registry.cpp`、`tools/project.cpp`、`tests/**`
4. `mcp_server: point the M1 acceptance gate at the renamed contract (GDR-16)`
   → `modules/mcp_server/scripts/accept_m1.ps1`

**不要动**（保持未跟踪，由决策者另行提交）：`.graphifyignore`、`build-m0.cmd`、`install-deps-m0.cmd`、`graphify-out/`、
`modules/mcp_server/docs/TOOL-NAMING.md`、`modules/mcp_server/docs/B0-BRIEF.md`。

## 5. 证据要求（不得伪造；回报里贴真实片段）

- S0 红、S2 红、S1 绿、S3 绿 四段 `[doctest] test cases: ... | ... failed` 结尾行 + 失败用例名清单；
- S7 的 MCP 单测、全引擎 `--test`（cases/assertions/failed 与退出码）、`accept_m1.ps1` 两次的逐项 PASS/FAIL 尾部与退出码；
- 生成脚本 stdout 原文 + `certutil`/`Get-FileHash -Algorithm SHA256` 的输出 sha256，以及「跑两次 sha256 相同」的证据；
- `git log --oneline -4`、`git status --porcelain`；
- 每条命令的**完整命令行**与工作目录。

---

## 6. 决策记录（决策者，B0 冻结）

| 编号 | 触发问题 | 结论 | 理由 / 影响 |
|---|---|---|---|
| D-E1 | `accept_m1.ps1` 的对等门参照物在新名落地后失效（旧 fixture 只有旧名） | 参照物切换为 `docs/tools_list.renamed.json`，`$ToolNames` 用新名 | §16 第 2 项已指定该文件为对等门参照物；description/inputSchema 由旧契约**机械搬运**，门禁强度不降；旧 fixture 仍作为 `_meta.generated_from` 留在溯源链上 |
| D-E2 | 动词闭集在 C++ 里硬编码，与映射表形成双份事实源 | 接受硬编码，并由生成脚本用同构谓词对 169 条新名做自检 | 注册期无法读 JSON；自检把「双份定义漂移」变成可复现的红 |
| D-E3 | L4（禁 `update_`）与 L2（动词闭集）都可能命中同一名字 | 校验顺序固定为 空名 → L4 → L1 → L2 → L3 | 让 L4 成为**可独立观测**的谓词；单测 D 用通道/动词都合法但含 `update_` 的名字证明这一点 |
| D-E4 | 是否要求 `<object>` 段必须存在 | **不要求**（L1 正则允许 `editor_get`） | 严格照 GDR-16 的谓词实现，不发明需求；留作后续批次开放项 |
| D-E5 | `channel`/`verb` 字段先落地会让既有的 2 个 M1 工具被闸门拒掉 | RED-1 用「宽松占位实现」取得原生红，GREEN-1 同一步补 `project.cpp` 的 `channel`/`verb` | 保证每个红都是「因缺行为而红」、每个绿都是全绿，避免出现「闸门已开但无工具」的中间态 |
| D-E6 | 引擎仓库无 DECISIONS.md，而 `F:\moonbit-hof-rs\DECISIONS.md` 在本任务中只读（D38/D41/D43 在此） | 本文件即 B0 的决策工件 | 遵守「只改 `modules/mcp_server/**`」的硬约束，同时不丢决策日志 |
| D-E7 | 独立验收发现：L1 正则 `[a-z0-9_]+` 允许以 `_` 结尾，于是 `os_get_` 被接受（对象段为空） | **不改**：这是 GDR-16 谓词的逐字实现 | 与 D-E4 同源（都不要求对象段）。记录为开放项，留待后续批次决定是否要求「对象段非空」；现在收紧属于发明需求 |

---

## 7. 验收结论（独立验收子代理，全新上下文，不采信实现者数字）

**verdict = pass，defects = 0。** 验收方自行重跑全部门并复核 13 项规范条款（C1–C13）与 5 道门（G1–G5）：

| 门 | 独立实测 |
|---|---|
| G1 构建 | `scons ... tests=yes` 退出码 0；因树已构建过，另做两次真实重链接验证提交源码可编译 |
| G2 模块单测 | `--test-case=[MCPServer]*` → **39 cases / 267 assertions / 0 failed**，退出码 0（改前基线 33 cases） |
| G3 全引擎 | `--test` → **1465 cases / 424548 assertions / 0 failed**（3 skipped），退出码 0 |
| G4 契约可复现 | 生成器跑两次 + 仓库交付物三方 sha256 全部相等 `452d686bf8ce3dda604d223c26dde803055b3187979742fd8e8f19e784afd537`；174→169 / merge 3 / unregister 2 |
| G5 验收脚本 ×2 | 两次均 **20/20 PASS**，退出码 0，SUMMARY 逐项一致；`guard_user_port_9877` PASS 且 `pid_before == pid_after == 36392` |

关键独立核对：169 条 description/inputSchema 与旧契约**逐条解析后完全相同**（0 处差异）；剔除项恰为
`navigate_to`/`export_project`，合并项恰为那 3 对且保留方都在输出里；`fix_implementation_first` 7 条全在；
C++ 闭集 37 词与映射表集合相等；**对抗性探针**（临时测试后已还原并哈希取证）实测：127 字符超长名被接受、
`editor_set_update_flag` 因 L4 被拒、`running_game_get_x` 声明 `editor` 因 L3 被拒、`editor_get`/`os_get_` 被接受（见 D-E4/D-E7）。

遗留风险（验收方列出，均**非缺陷**）：① `os_get_` 这类「对象段为空」的名字被接受（D-E7 的开放项）；
② push 状态只能推断（该分支无 upstream，`origin/feature/mcp-server-module` 不存在）；
③ 对抗性探针走的是 C++ API 与注册路径，未在 HTTP 线上注入超长/空对象名（线上路径由 accept 脚本 case3/case12 间接覆盖）。
