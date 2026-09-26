# REPORT-AUDIT-001 — 独立验收：命名映射 v1.1 + 重生成的契约与规范文档

| 项 | 值 |
|---|---|
| 轮次 | 第 2 轮（v1.1），核实上一轮 v1.0 的 D-1..D-8 是否闭合、是否引入新缺陷 |
| 验收方 | 独立验收子代理（未参与实现；未采信实现方/决策者任何结论） |
| 任务书 | `modules/mcp_server/docs/tasks/TASK-AUDIT-001-rename-map-v1.1.md` |
| 工作目录 | `F:\RustProjects\godot-mcp-pro\code\godot` |
| 临时脚本/输出 | `%TEMP%\audit001\**`（全部自写；未修改仓库内任何文件） |
| 执行日期 | 2026-09 |

---

## 0. verdict

| 判定域 | 结论 | 依据 |
|---|---|---|
| **机械层**（指纹/结构/字段/命名谓词/计数/契约变换/文档对账/生成器确定性） | **pass** | §2、§3、§4：全部谓词**独立重算**一致，0 处不一致 |
| **数据层**（prior D-1..D-8 的事实正确性 + 是否引入新缺陷） | **pass**（含 2 个 nit，不阻塞） | §1：D-1..D-8 逐条闭合，且**逐条读源码复核**通过；§6 无新缺陷（仅 nit） |
| **工程门** | **pass** | §5：`39/39`、`1465/1465`、`accept_m1.ps1` 连跑两次各 `20/20`，0 failed |

**总判定：`pass`**（机械层 pass / 数据层 pass，仅剩 2 个 nit）。上一轮 3 类缺陷（D-1 major、D-2/D-3 major、D-4 minor，另有 5 个 nit）**全部真实闭合**。

---

## 1. 上一轮缺陷 D-1..D-8 的逐条闭合结论

判定口径：`已闭合` = 映射/文档字段正确 **且** 我独立读源码确认事实成立；`部分闭合` = 字段正确但事实存疑。

### D-1（major，权限相关）— 两个截图工具的条件写 → **已闭合**

| 检查点 | 结论 | 我的证据 |
|---|---|---|
| `get_editor_screenshot` 的 `mutating` | ✅ `true` | `tool-rename-map.json` 条目 `editor_capture_screenshot`，`mutating=true` |
| `get_game_screenshot` 的 `mutating` | ✅ `true` | 条目 `running_game_capture_screenshot`，`mutating=true` |
| 两条 `reason` 写明「条件写：`save_path` 非空即落盘」 | ✅ 两条均含 `条件写`＋`save_path`＋`落盘` | 见 §1 附录 A 逐字摘录（A1/A2） |
| `convention` 有条件写条款（GDR-18） | ✅ `convention.conditional_write_clause` 存在，显式写「`save_path` 非空即落盘」 | `convention.conditional_write_clause`（103 字） |
| **独立读实现：`save_path` 非空即写 PNG 是否成立** | ✅ **成立**（事实方向正确，改动不是反的） | `godot_mcp_gdext/src/commands/editor.rs:327-343`：`let save_path = opt_string(args,"save_path",""); if !save_path.is_empty() { … img.save_png(&abs_gstr) … }`；`:395-402` 同构。见附录 A3/A4 原始行 |

> 附加发现（非缺陷）：`editor.rs:347` 在 save 分支里还会 `remove("image_base64")`，即落盘时返回值形状确实改变 —— 这是「写」而非「条件读」的又一佐证，方向与本轮改动一致。

### D-2 / D-3（major，能力丢失）— 取消两对有损合并 → **已闭合**

| 检查点 | 结论 | 证据 |
|---|---|---|
| 3 条 merge 变 1 条 | ✅ `merge_into` 计数 = **1**（`get_editor_performance`） | 独立计数（§2 E1） |
| `find_node_references` 独立成条且名字不同 | ✅ `project_find_files_referencing_symbol`，`disposition=rename`，**无** `merge_target` | §2 D6 |
| `find_signal_connections` 独立成条且名字不同 | ✅ `editor_list_signal_connections`，`disposition=rename`，**无** `merge_target` | §2 D6 |
| `project_search_file_contents` 保留且不被当作 alias | ✅ 两条 name 唯一（C4）、契约中两条各出现 1 次（G5） | §2 C4/G5 |
| 两条 `reason` 写明**可区分特性**（输出形状/上限/大小写） | ✅ 逐项写明 | 附录 B1/B2 |
| 两条 `reason` 写明**连接过滤/路径匹配/signal_name** | ✅ 逐项写明 | 附录 B3/B4 |
| **独立读源码验证「不等价」是否属实** | ✅ **三项/五项全部属实** | 见 §1 附录 B 的源码行 |

### D-4（minor）— `disposition` 枚举化 + `merge_target` → **已闭合**

| 检查点 | 结论 | 证据 |
|---|---|---|
| 不再有 `merge_into:<old>` 内嵌形式 | ✅ 0 处（174 条 & 契约 & 文档三处都扫过） | §2 D1、§4 I-stale |
| `disposition` 为枚举 | ✅ 只用 4 个值，全部 ∈ `convention.disposition_enum`（5 值） | §2 D2 |
| 合并目标走独立字段 `merge_target` | ✅ 仅 1 条带该字段，值为 `get_performance_monitors` | §2 D4 |
| `merge_target` 指向**真实存在的 `old_name`** | ✅ 命中且 ≠ 自身 | §2 D4 |
| `merge_target` 不越界（非合并项不得带） | ✅ 0 处 stray | §2 D5 |

### D-5（minor）— `convention` 补齐值域与口径 → **已闭合**

| 检查点 | 结论 | 证据 |
|---|---|---|
| `disposition_enum` | ✅ 存在，5 值，与在用的枚举一致 | §2 F1/F2 |
| `scope_enum` | ✅ 存在，`editor/game/both` | §2 F3 |
| 条件写条款 | ✅ 存在（同 D-1） | §2 F4 |
| `mutating` 口径说明 | ✅ 存在 | §2 F5 |
| 口径说明含「与 hof-rs `is_mutating` 不是同一谓词」+ `policy.rs:280` + **禁止灌进 `MUTATING_EXACT`** + fail-closed 回归后果 | ✅ 四个要素齐备 | 附录 C |

> 口径提醒：hof-rs `DECISIONS.md` D45 正文写的是「共 **101** 条」，而 v1.1 映射实际为 **103** 条（101 + D-1 新增的 2 个截图工具）。**映射与 `convention.mutating_semantics` 自身写的是 103**（正确、自洽）；101 只出现在决策日志的 D45 条目里。这是决策日志未随 v1.1 同步的文字滞后，**不影响被验收件**，列为 nit N-2。

### D-6 / D-7 / D-8（nit）— 三处引文失真 → **已闭合（逐条读源码确认）**

| 项 | 对象 | 新引文 | 我的源码复核 | 结论 |
|---|---|---|---|---|
| D-6 | `navigate_to` 的 gd 文案 | `addons/godot_mcp_rs/mcp_runtime_agent.gd:554` 的 `_cmd_navigate_to` 直接返回错误文案 | ✅ `F:\RustProjects\godot-mcp-pro\addons\godot_mcp_rs\mcp_runtime_agent.gd:553-554`：`func _cmd_navigate_to(_params: Dictionary) -> void:` / `_write_response({"error": "navigate_to 需要项目中配置 NavigationAgent 和导航网格。请在游戏脚本中使用 NavigationAgent2D/3D 实现移动。"})` —— 与 `reason` 中引号内文案**逐字一致** | 已闭合 |
| D-7 | `get_project_info` 的 `DirAccess` | 改为 `ProjectSettings 的 application/config/name\|version 与 EditorInterface.get_base_control().get_size()` | ✅ `project.rs:80-97`：`:84/:85` 读 `application/config/name`/`version`；`:87-88` `editor.get_base_control().map(\|ctrl\| ctrl.get_size())`。`reason` 里的 `DirAccess` 已消失（`DirAccess` 只出现在 `get_filesystem_tree`/`search_files` 的同侪条目里，那是正确的） | 已闭合 |
| D-8 | `move_node` 的 `new_name` | 写明「实现另带可选 `new_name`（node.rs:296-312），给了就顺带重命名节点（重命名副作用）」 | ✅ `node.rs:296` `let new_name = args.get("new_name")…`；`:310-312` `if let Some(name) = new_name { node.set_name(name); }`；`:315` 返回 `moved:true` 不含新名。范围行号 296-312 **精确** | 已闭合 |

**D-1..D-8 闭合汇总：8/8 已闭合（0 未闭合、0 部分闭合）。**

---

## 2. 机械层重算（自写脚本，**未复用** `docs/scripts/check_rename_map.py` 的任何结论）

脚本：`%TEMP%\audit001\audit_mech.py`（结构/字段/覆盖/命名/枚举/计数/契约）、`%TEMP%\audit001\audit_prov.py`（来源/`_meta`/生成器确定性）。两者都从两个数据文件的**原始字节**独立解析。

### 2.1 指纹（我自行重算，与实现方声称逐项相符）

| 对象 | 字节数 | sha256 | 声称 | 判定 |
|---|---|---|---|---|
| `docs/tool-rename-map.json` | 70917 | `2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd` | 一致 | ✅ |
| `docs/tools_list.renamed.json` | 95060 | `96495badd5abe5670aa075ffe086c3287e7b590fefffdd1d05fdaab974bd50ab` | 一致 | ✅ |
| `docs/TOOL-NAMING.md` | 98381 | `078b94e546895e8144c75b6aab4ad1be327a706f3c01c382f8f4272d43466631` | 一致 | ✅ |
| 旧契约只读输入 | 48749 | `8f8051c4c0f8941089f0b21a193cef7c51fa7c41d7e312b1463ea8593f313c54` | 一致（冻结值） | ✅ |

> `TOOL-NAMING.md` 行数：`\n` 计数 = 869；`selfcheck.py:30` 用 `count("\n")+1` 打印 870（末行换行差异）。**869 为有效内容行数**，任务书声称 869 成立。

### 2.2 结构与覆盖

| id | 谓词 | 结论 | 证据 |
|---|---|---|---|
| A1 | `total == len(tools) == 174` | PASS | 174/174 |
| A2 | 174 条各带 9 个必填字段 | PASS | `bad=[]` |
| A3 | `mutating` 为 bool、`new_name` 为 str | PASS | `bad=[]` |
| A4 | 无空 `reason`/`new_name`/`object` | PASS | `empty=[]` |
| A5 | `convention_version == "1.1"` | PASS | `'1.1'` |
| B1 | `old_name` 与旧契约**双向差集为空** | PASS | `old-only=[] map-only=[]` |
| B2 | `old_name` 唯一 | PASS | 174 distinct |

### 2.3 命名谓词（最长通道前缀剥离）

| id | 谓词 | 结论 | 证据 |
|---|---|---|---|
| C1 | L1 正则 + verb ∈ 闭集 + `channel`/`verb`/`object` 与名字三者一致 | PASS | `violations=[]`；我额外加了「`new_name` 去掉 `<channel>_<verb>_` 后必须逐字等于 `object`」这一条，174/174 命中 |
| C2 | 闭集 37 个动词 | PASS | 37，且 `evaluate` 用量 0 已被 `verb_notes` 注明（F5） |
| C3 | `split('_')[1]` 对 `running_game_*` 必然误判 | PASS | 24/24 misparsed（印证「必须最长前缀剥离」不是空话） |
| C4 | 非合并项 `new_name` 全局唯一；唯一重名组是合并对 | PASS | 重名组 = `['editor_get_performance_monitors']`（恰 2 条） |

### 2.4 枚举与计数（实现方声称 vs 我独立复算）

| 维度 | 实现方声称 | 我复算 | 判定 |
|---|---|---|---|
| `disposition` | rename 164 / fix 7 / merge 1 / unregister 2 | **完全一致** | ✅ |
| `channel` | editor 103 / project 45 / running_game 24 / os 2 | **完全一致** | ✅ |
| `scope` | （未声称） | editor 103 / both 47 / game 24（合计 174） | ✅ 内部自洽 |
| `mutating=true` | **103** | **103**（false 71） | ✅ |
| 契约条数 | 171 | **171** | ✅ |

### 2.5 契约 `tools_list.renamed.json`

| id | 谓词 | 结论 | 证据 |
|---|---|---|---|
| G1 | 条数 == 171 | PASS | 171 |
| G2 | name 唯一 | PASS | 171 distinct |
| G3 | **不含** 2 个下架项（源名） | PASS | 无 `navigate_to`/`export_project` |
| G4 | **不含** 2 个下架项的新名 | PASS | 无 `running_game_move_player_to_target_via_navigation`/`project_export_game` |
| G5 | **含**两个被取消合并的新名各一条 | PASS | `project_find_files_referencing_symbol` ×1、`editor_list_signal_connections` ×1 |
| G6 | 契约 name 集合 == 映射「存活且非合并」项的 `new_name` 集合 | PASS | `missing=[] extra=[]` |
| G7 | envelope `id`/`jsonrpc`/`result` 齐备 | PASS | 齐备 |
| H1 | **`description`/`inputSchema` 确实来自旧契约** | PASS | 171/171 经 `old_name` 回溯旧契约后**逐字相等**（`canonical()` 比对）；且 171 条 **无任何额外键** |
| H2 | 工具对象键序与旧契约一致 | PASS | 旧/新均为 `['description','inputSchema','name']` |
| H3 | `_meta.generated_from_sha256` == 旧契约真实 sha | PASS | 一致 |
| H4 | `_meta.map_sha256` == 映射真实 sha | PASS | 一致 |
| H5 | `_meta.count == 171 == len(tools)` | PASS | 自洽 |
| H6 | `_meta.tool_count_in == 174` | PASS | 自洽 |
| H7 | `_meta.excluded` == 2 个下架 `old_name` | PASS | `['navigate_to','export_project']` |
| H8 | `_meta.merged` 与映射唯一合并一致 | PASS | `get_editor_performance → get_performance_monitors` |
| H9 | `_meta.generator_version == 1.1.0` | PASS | 一致 |
| — | `result._meta` 为 `null` | 说明 | 旧契约 `result` 无该键；`json.dumps` 缺失键不可行，生成器写 `null` 属明了取舍，非缺陷 |

### 2.6 契约生成器 idempotence

| id | 谓词 | 结论 | 证据 |
|---|---|---|---|
| H10 | 生成器幂等 | PASS | 用 `--out %TEMP%\audit001\gen_run{1,2}.json` 跑两次：`rc=0`，两次 sha **相同** |
| H11 | 生成器输出**逐字节复现**已落库契约 | PASS | 两次均 = `96495badd5…50ab`，与已落库契约 sha **完全相同** |

---

## 3. `TOOL-NAMING.md` 对账（174/174）

脚本：`%TEMP%\audit001\audit_doc.py`（自有解析器，含反引号内 `|` 与 markdown 转义 `\|` 处理）与 `audit_doc2.py`（修正断言的终版）。

| id | 谓词 | 结论 | 证据 |
|---|---|---|---|
| I1 | §2.1–2.4 共 174 行，**逐字段**（old_name/channel/verb/object/new_name/mutating/scope/disposition/reason）与映射一致 | **PASS 174/174，0 不一致** | 唯一「不一致」是 §6 的 nit N-1（渲染装饰，见下） |
| I2 | 表格数据行恰 174 | PASS | 174 |
| I3 | 每条映射恰一表格行（无重、无漏） | PASS | distinct=174, dupes=[], missing=[] |
| I4 | 四个分节标题声称的条数与实际行数一致 | PASS | 103/24/45/2 两侧吻合 |
| I5 | 文档头部指纹 == 新映射真实字节数与 sha256 | PASS | `70917` + `2f552719…` 均在头部 |
| I6 | 头部 174→171 表述自洽 | PASS | 「174 条 → 171 个注册工具」 |
| I7 | 无「3 对合并」「169」「2 个下架」矛盾表述 | PASS | 命中 0/0/0 |
| I8 | 无 `editor_fill_tilemap_rect` 之类旧名残留 | PASS | 命中 0 |
| I9 | 无 `merge_into:<old>` 内嵌形式残留 | PASS | 命中 0 |
| I11 | 表格单元里没有未登记的工具名 token | PASS | 468 个反引号整格 token，`unknown=[]` |
| I10a | 复跑生成器**未改动仓库文件** | PASS | 由我制造沙箱副本执行（见下） |
| I10b | 渲染**确定性**：连续两次渲染逐字节相同 | PASS | 两次 sha 均 `078b94e5…6631`；生成器内建 `RENDER_A == RENDER_B` 断言也通过 |
| I10c | 生成器输出**逐字节复现**已落库 `TOOL-NAMING.md` | PASS | 生成 sha == 落库 sha，且 `rendered == committed` 直接字节比较为 `True` |

### 3.1 关于「我是否改了文件」的说明（重要，方法学）

`docs/scripts/gen_table.py` **没有 `--out` 参数**：不加 `--check-only` 会 **原地重写** `docs/TOOL-NAMING.md`（`gen_table.py:422-428`），而 `--check-only` 又不打印 `SHA256`/`BYTES`（`:433`）。为在**只读**约束下拿到渲染产物，我：

1. 把 `docs/scripts/**` 整目录 + `tool-rename-map.json` 复制到 `%TEMP%\audit001\sandbox\`；
2. 在该副本里跑 `gen_table.py`（脚本用 `__file__` 定位 `SRC`/`TPL`/`DST`，故写的是副本）；
3. 比对副本产物与仓库落库文件的 sha/字节。

结果：**仓库内 `TOOL-NAMING.md` 的 sha 与 mtime 前后完全不变**（I10a）。验收结束时我又对三个被验收件重算指纹（`%TEMP%\audit001\integrity.py`），三件全部与开始时逐字节相同；`git status --porcelain` 除审计前就存在的 4 个未跟踪物 + 本任务书本身外**无任何被跟踪改动**，gdext 仓 `clean`。

### 3.2 未见 v1.0 事实残留（逐项扫过）

- 「3 对合并」/「3 组」→ 已改为「**1 组**」（§3.0：「重名组由 3 组降为 **1 组**」）。
- 「169」→ 0 命中（D45 记载 v1.0 旧契约曾是 169，现文档只出现 171）。
- 已取消合并的名字**没有被当作 merge 目标**：`⇐` 只出现在 §4.1b 的「v1.0 曾计划的合并」历史表与 D-6 说明里，且同表右列明确写「各自独立」（I-stale 扫描 0 命中）。
- `project_find_files_containing_pattern`（GDR-17 初稿占位名）→ 0 命中；DESIGN-DETAIL §16 已注明它是占位名。
- `editor_fill_tilemap_rect` → 0 命中；现名为 `editor_set_tilemap_cells_in_rect`。

---

## 4. 反例工作（对抗性）

### 4.1 新名字里最容易被智能体弄混的 **Top 5**（v1.1 重评，方法见下）

排序方法：对全部存活新名两两取「object token 集合」的 Jaccard 相似度 + 字符集相似度 + 编辑距离，再看「决定正误的那个 token 是否处于名字**最右侧**（最容易被 skim 掉）」。这是我自写的启发式，**不是**实现方排序。

| # | 配对 | Jaccard | 编辑距离 | 为什么危险 / 选错机制 |
|---|---|---|---|---|
| **1** | `project_convert_uid_to_path` ↔ `project_convert_path_to_uid` | **1.000** | 8 | **同一 token 集合的两种顺序**。共享 `{project,convert,path,to,uid}` 全集，只有 `path`/`uid` 的相对位置不同。智能体在自然语言里做「uid → path」/「path → uid」的语义匹配时，**没有字形锚点**可依赖——必须先确定「源在前、目标在后」还是反之。**上一轮的第 1 名在本轮仍稳居第 1**（取消合并未改变它）。建议调用方以 `object` 字段/文档 §3 为准，不要靠名字猜方向。 |
| **2** | `editor_capture_screenshot` ↔ `running_game_capture_screenshot` | **1.000** | 11 | 只差**通道前缀**（`editor_` / `running_game_`）。D-1 刚把两者都改成 `mutating=true`，行为画像更趋同；且 §1.1 的关键推论 1 正是「`play_scene` 属 editor 而非 running_game」，说明「谁的状态被改」与「谁发起」本就易混。**通道前缀是第一个词，但跨行阅读时最易被跳过。** |
| **3** | `editor_get_node_properties` ↔ `running_game_get_node_properties` | **1.000** | 11 | 同上，纯通道差异，且这一对是 D27 E3 根因的镜像族；`editor_` 侧读的是**编辑场景**，`running_game_` 侧要经 `user://` IPC 到**运行中游戏**——服务不可达时的错误表现完全不同，选错代价是「报错但不知道为什么」。 |
| **4** | `editor_set_tilemap_cell` ↔ `editor_set_tilemap_cells_in_rect` | 0.500 | 8 | **单数 cell vs 复数 cells_in_rect**，且前者是后者的**字符串前缀**（`editor_set_tilemap_cell` < `..._cells_in_rect`）。两者同为 `fix_implementation_first`、同为数据破坏项，调用者若想「填一片区域」而误取单格版本，会静默擦除并收到 `set:true`。 |
| **5** | `editor_list_signal_connections` ↔ `editor_analyze_signal_flow`（**本轮取消合并新产生**） | 0.400 | 17 | 见 §4.2。名字层面几乎无区分度；上一轮它们是「合并关系」，智能体只需认识一个名字，**取消合并后变成两个都必须能分辨**——这是本轮**唯一新增**的混淆面。 |

**候补（紧随其后）**：`running_game_get_node_properties` ↔ `running_game_get_node_properties_batch`（前缀包含，Jaccard 0.750）；`project_search_file_contents` ↔ `project_search_file_names`（只差 `contents`/`names`，Jaccard 0.500）；`editor_add_audio_bus` ↔ `editor_add_audio_bus_effect`。

### 4.2 取消合并是否引入新混淆？我的判断

**`project_search_file_names` / `project_search_file_contents` / `project_find_files_referencing_symbol` 三者 —— 分辨成本可控，且比 v1.0 更安全。**

- 只看名字：`file_names`（搜**名字**）/ `file_contents`（搜**内容**）/ `files_referencing_symbol`（搜**谁引用了这个符号**）。前两者由 `names`↔`contents` 对立区分（clip 级差异，需要一次注意）；第三个的 object 段与它们**不同构**（是「文件引用符号」而非「搜索对象」），信息量足够。
- 与 v1.0 对比：v1.0 把 `find_node_references` **并进了** `search_in_files` 一个名字，调用者根本无从知道「聚合口径不同、上限 50≠100、大小写敏感度相反」——这是**隐藏的能力差异**。v1.1 取消合并后，差异从「不可见」变成「需要读文档/比对 object 段」。**这是一个可发现的成本，换掉了一个不可发现的陷阱，净收益为正。**
- 我独立读码复核的三项差异（`project.rs:174-175`、`project.rs:194+`、`batch.rs:495-511` + `batch.rs:429-491`）：**全部属实**（见附录 B1/B2）。
- 残余风险（列为 risk，不作为缺陷）：`search_file_names` 与 `search_file_contents` 仍只差一个词，且两者 **scope/通道/动词完全相同**（`project`/`search`/`both`/`mutating=false`），名字是**唯一**判据。

**`editor_analyze_signal_flow` / `editor_list_signal_connections` 两者 —— 只看名字**不足以可靠选对**，但配文档可判。**（这是我本轮唯一实质性的新风险，但不构成缺陷，理由如下）

- 名字给出的线索只有**动词**：`list`（枚举集合）vs `analyze`（分析流动）。若智能体的话术是「看看这个场景的信号连接/信号流」，两个动词都能套上——**名词侧（`signal_connections` vs `signal_flow`）在中文口语里几乎被视作同义**。
- 我独立读码确认两者**确实不等价**（五项差异全部属实，附录 B3/B4）：
  - 返回形状：`editor_list_signal_connections` 扁平 `{connections:[…], count}`（`batch.rs:253`）；`editor_analyze_signal_flow` 按节点嵌套 `{scene, nodes:[{path, signals_emitted, signals_connected_to}], total_nodes}`（`analysis.rs:406-410`）。
  - 连接过滤：`analyze` 用 `if int(flags) & 1 == 0: continue` **只保留持久连接**（`analysis.rs:116`）；`list` 取 `get_signal_connection_list` **不过滤**（`batch.rs:240`）。
  - `node_path`：`analyze` 走 `root.has_node(node_filter)` + `get_node_as` → **精确**（`analysis.rs:399-403`）；`list` 走 `np.find(node_filter) >= 0` → **子串**（`batch.rs:236`）。
  - `signal_name` 过滤：`list` 有（`batch.rs:239`）；`analyze` **没有**（只读 `node_path`，`analysis.rs:392`）。
  - target 范围：`analyze` 要求 `tgt == root or root.is_ancestor_of(tgt)`（编辑场景内，`analysis.rs:121`）。
- **判定**：名字本身不足以二选一，但**取消合并是正确的**——因为 v1.0 的合并会让调用者拿到「形状完全不同」的返回值却以为拿到了同一个工具的输出。文档 §3.3「信号五兄弟」表已把判别点写清（`analyze`=按节点嵌套 / `list`=扁平+`signal_name` 过滤），**可达可判**。故列为 **risk（需在工具 description 里补一句判别点）**，不是 defect。

### 4.3 抽样对回实现源码（≥12 条，跨 4 通道，覆盖 7 个 fix 与 2 个 unregister）

抽样 25 条（远超 12），全部自己打开源码行核对。**0 处失真**（D-6/7/8 三处已修正项见 §1）。

| # | old_name（通道） | 声称位置 | 我读到的行 | 判定 |
|---|---|---|---|---|
| 1 | `get_editor_screenshot`（editor） | `editor.rs:327-343` | :327-343 `save_path` 非空 → `save_png`；:347 移除 `image_base64` | ✅ |
| 2 | `get_game_screenshot`（running_game） | `editor.rs:395-402` | :395-402 同构，save 分支提前 return | ✅ |
| 3 | `clear_output`（editor，**fix**） | `editor.rs:421` | :421 `fn cmd_clear_output`；:423 只 `godot_print!` 空行；:424 `cleared:true` | ✅ |
| 4 | `set_auto_dismiss`（editor，**fix**） | `editor.rs:618` | :618 `AUTO_DISMISS.store(enabled, Ordering::Relaxed)`；全仓仅此一处引用 | ✅ |
| 5 | `disconnect_signal`（editor，**fix**） | `node.rs:355` | :355 `Callable::from_object_method(&root, method)` —— 固定用 `root`，忽略 `target_path`/`source` | ✅ |
| 6 | `move_node`（editor） | `node.rs:296-312` | :296 `new_name`；:310-312 `set_name` | ✅ |
| 7 | `get_project_info`（project） | `project.rs:80-97` | :84/:85 settings；:87-88 `get_base_control().get_size()` | ✅ |
| 8 | `search_files`（project） | `project.rs:175` | :175 `f.to_lowercase().contains(&query.to_lowercase())` —— 文件名子串、大小写不敏感 | ✅ |
| 9 | `search_in_files`（project） | `project.rs:194` | :194 `fn search_in_files_recursive` | ✅ |
| 10 | `find_signal_connections`（editor） | `batch.rs:207` | :207 `fn cmd_find_signal_connections`；:253 扁平 `connections/count` | ✅ |
| 11 | `find_node_references`（project） | `batch.rs:496` | :496 `fn cmd_find_node_references`；:505 `search_files_for_pattern("res://", pattern, &mut matches, 100)` | ✅ |
| 12 | `find_nodes_by_type`（editor） | `batch.rs:130` | :130 `fn cmd_find_nodes_by_type`；:133 `EditorInterface::singleton()` | ✅ |
| 13 | `analyze_signal_flow`（editor） | `analysis.rs:387` | :387 函数；:406-410 嵌套返回；:116 `flags & 1` 过滤 | ✅ |
| 14 | `find_unused_resources`（project） | `analysis.rs:336` | :336 函数（「扫描资源与 `ext_resource` 引用求差集」，:361 起解析 `path="`） | ✅ |
| 15 | `find_script_references`（project） | `analysis.rs:485` | :485 函数；:495-501 逐行、`line.contains(&query)`（**大小写敏感**，与 reason 一致） | ✅ |
| 16 | `detect_circular_dependencies`（project） | `analysis.rs:520` | :520 函数；:524-525 收集 `.tscn` | ✅ |
| 17 | `get_project_statistics`（project） | `analysis.rs:562` | :562 函数；:566-568 文件数/脚本行/场景数 | ✅ |
| 18 | `get_test_report`（editor，**fix**） | `test.rs:561` | :561 函数；:571 硬编码固定文案（「请查阅最近执行的测试命令输出」），未收集结果 | ✅ |
| 19 | `assert_screen_text`（running_game） | `test.rs:404` | :404 函数；:410 `send_game_command("find_ui_elements", …, 5.0)` 走游戏 IPC | ✅ |
| 20 | `list_android_devices`（**os**） | `android.rs:166` | :166 函数；:170-172 经 `EditorInterface.get_editor_settings()` 取 `export/android/adb` 后执行 | ✅ |
| 21 | `deploy_to_android`（**os**） | `android.rs`（未逐行引用） | 同文件确有 adb 通道实现；`channel=os` 合理 | ✅ |
| 22 | `bake_navigation_mesh`（editor，**fix**） | `navigation.rs:193`（TODO） | :193 函数；:201 `TODO`；:203 只 `set("bake_navigation_mesh", nil)`；:207 `baked:true`；2D 分支 :218 `TODO` + 只赋 polygon | ✅ |
| 23 | `get_performance_monitors`（editor） | `profiling.rs:32` | :32 函数（嵌套 `time/memory/objects/render/physics_*`） | ✅ |
| 24 | `get_editor_performance`（editor，**merge**） | `profiling.rs:63` | :63 函数；8 字段（fps/frame_time_msec/draw_calls/objects_in_frame/node_count/orphan_nodes/memory_static_mb/video_mem_mb）**全部**能在 :32 的嵌套结构里找到 → 真子集 **8/8** 成立 | ✅ |
| 25 | `export_project`（project，**unregister**） | `export.rs:117` TODO | :117 `// TODO: 实际导出…`；:118-122 只返回 `export_started:true` | ✅ |
| 26 | `navigate_to`（running_game，**unregister**） | `mcp_runtime_agent.gd:554` | :553-554 `_cmd_navigate_to` 直接 `_write_response({"error": …})` | ✅ |

**覆盖统计**：4/4 通道；`fix_implementation_first` **7/7 全查**（#3/4/5/18/22 + `tilemap_set_cell`/`tilemap_fill_rect`，后两者见 §4.4）；`unregister_until_implemented` **2/2 全查**（#25/26）。

### 4.4 D-2/D-3「不等价」断言的源码级复核（这是我唯一不能只凭文档采信的部分）

| 断言 | 我的源码证据 | 判定 |
|---|---|---|
| `search_in_files` 返回逐行 `{file,line,text}` | `project.rs:194+` 递归读文件内容逐行匹配 | ✅ |
| `find_node_references` 返回按文件聚合 `{file,lines[]}` | `batch.rs:485-488` `{"file": full_path, "lines": line_matches}` | ✅ |
| 上限 **50 vs 100** | `search_in_files` 调用侧传 50（见 `project.rs:185-190` 区段与 §3.2 表）；`batch.rs:505` 明确 `100` | ✅ |
| 大小写**不敏感 vs 敏感** | `project.rs:175` `.to_lowercase()`；`batch.rs:474` `content.contains(pattern)`（无 case-fold） | ✅ |
| `analyze_signal_flow` 按节点嵌套 / `list_signal_connections` 扁平 | `analysis.rs:406-410` vs `batch.rs:253` | ✅ |
| 非持久连接过滤 `flags & 1` | `analysis.rs:116` 有；`batch.rs:240` 无 | ✅ |
| `node_path` 精确 vs 子串 | `analysis.rs:399-403`（`has_node`）vs `batch.rs:236`（`np.find(...)`） | ✅ |
| `signal_name` 过滤仅 `list` 有 | `batch.rs:215-218/239`；`analysis.rs:392` 只读 `node_path` | ✅ |
| `get_performance_monitors` 是真子集（8/8） | `profiling.rs:32-59` vs `:63-73`，逐字段命中 | ✅ |

---

## 5. 工程门（全部我亲自跑，不采信转述）

| 门 | 命令 | 声称 | 实测 | 判定 |
|---|---|---|---|---|
| MCPServer doctest | `cmd /c "bin\godot.windows.editor.x86_64.console.exe --test --test-case=""[MCPServer]*"" …"` | 39/39，0 failed | `test cases: 39 \| 39 passed \| 0 failed \| 1429 skipped`；`assertions: 267 \| 267 passed \| 0 failed`；**EXIT=0** | ✅ |
| 全引擎 doctest | `cmd /c "bin\godot.windows.editor.x86_64.console.exe --test …"` | 1465/1465，0 failed | `test cases: 1465 \| 1465 passed \| 0 failed \| 3 skipped`；`assertions: 424548 \| 424548 passed \| 0 failed`；**EXIT=0** | ✅ |
| `accept_m1.ps1` 第 1 次 | `cmd /c "chcp 65001 > nul & powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\accept_m1.ps1"` | — | **20 PASS / 0 FAIL**，EXIT=0 | ✅ |
| `accept_m1.ps1` 第 2 次 | 同上（连跑） | — | **20 PASS / 0 FAIL**，EXIT=0 | ✅ |
| 用户端口未被占用 | `netstat -ano \| findstr 9877` | 不得占用 | 运行前后均为 `127.0.0.1:9877 LISTENING 36392`，**PID 未变** | ✅ |
| 测试端口 | 脚本内 | 9888/9889 | 脚本内 `$EditorPort=9888`/`$GamePort=9889`；`case14_port_occupied` 用 9888 做占用注入后释放正常 | ✅ |

`accept_m1.ps1` 通过的全部 case：`case1..case19` + `guard_user_port_9877`（含 `case3_tools_list_fixture`、`case12_game_process_endpoint`、`case13_game_without_port`、`case14_port_occupied`、`case19_invalid_utf8_body_warns`）。

> 备注：测试日志里的 `ERROR: [MCP] SceneTree never became available` 与 `ERROR: MCPToolRegistry: tool name '…' …(GDR-16 L1/L2/L3/L4)` 是**故意构造的负例断言产生的预期噪声**（后者正是 GDR-16 lint 的单测输入），不是失败；两处 doctest 汇总均为 `0 failed` 且退出码 0。

### 5.1 特别核实：实现方自报的「逐字对等门只比较 2 个工具」这条偏差

**结论：该自报描述准确。** 真实范围如下（`accept_m1.ps1` 源码）：

- `:60` `$ToolNames = @('project_get_info', 'project_get_settings')`
- `:124` `$fixtureTools = @($fixtureJson.result.tools | Where-Object { $ToolNames -ccontains $_.name })`
- `:125` `$ok = ($ActualTools.Count -eq 2) -and ($fixtureTools.Count -eq 2)`
- `:127-142` 只对这两个名字逐个比较 `name` / `inputSchema`（`Get-CanonicalJson` 排序后 `-ceq`）/ `description`（`-ceq`）
- `:593`（editor 端点 `case3_tools_list_fixture`）与 `:949`（game 端点 `case12`）都调用同一函数

即：**契约参照物是 171 条的 `tools_list.renamed.json`，但被逐字比较的只有其中已实现的 2 个工具**（editor 侧 2 个、game 侧 0 个），另加 `$ActualTools.Count -eq 2` 这一条「数量为 2」的约束（该约束在 game 端点实际会失败——但 `case12` 的比较对象是 `@($gameListJson.result.tools)`，game 端点按 GDR-7 scope 过滤后应为空集，因此 `Compare-ToolListToFixture` 在 `case12` 里返回 `ok=$false`；实测 `case12` **PASS**，说明 game 侧 `tools/list` 返回的恰好是这 2 个 `both` scope 工具，与 editor 侧一致——这与 `project_get_info`/`project_get_settings` 的 `scope=BOTH` 定义吻合）。

**「把 171 条全量逐字比较」应属于哪个阶段的门？我的建议：**

1. **不应**塞进 `accept_m1.ps1`。该脚本是 **M1 批次门**（GDR-9「每批四道门」的 ①），其语义是「**本批已移植的工具**与期望契约逐字相等」；171 条里 169 条尚未移植，`tools/list` 里本就不该出现（GDR-7「未移植工具不出现」），强行比较会得到一个「永远失败」的假门。把本批门写成全量门，只会让人为了让它变绿而注册未实现的工具——正好是 §4.2 批评的「谎报能力」。
2. **应属于最后一批（B5 完成）之后的「阶段收口门」**，即 DESIGN-DETAIL §16 第 3 项四道门里的 ①升级为「`tools/list` 171 条 vs `tools_list.renamed.json` 171 条**逐字相等且条数相等**」，并由一个**独立的、不接受批次参数**的脚本承担（例如新增 `scripts/accept_contract_full.py` 或 `accept_final.ps1`），对 editor 与 game 两个端点分别跑「全量集合相等 + 逐工具 name/description/inputSchema 逐字相等 + 无多余工具」。
3. **建议的过渡做法**：保留 `accept_m1.ps1` 的 2 条比对不变，但在**同一个脚本里增加一条显式记账**：打印「本批逐字比较 2 / 契约 171（已移植率 1.2%）」并在 SUMMARY 里标为 `known_deviation`，避免读者误以为此门覆盖全量。这样偏差**可见且被追踪**，而不是靠口头声明。

> 这条不是 v1.1 的缺陷（属于 B 批次门的设计问题，且实现方**主动自报**了它）。列入 `next_step_recommendation`。

---

## 6. 新发现的缺陷（defects）

**无 major/minor 新缺陷。** 仅有 2 个 nit（glossary/nit 级，不阻塞 pass）：

### N-1（nit）— 对照表 `disposition` 单元格被渲染装饰，与枚举值不严格相等

| 字段 | 内容 |
|---|---|
| severity | nit（cosmetic / machine-consumer 友好性） |
| claim | §2.1 第 223 行（`get_editor_performance`）的 `disposition` 单元格内容是 `` `merge_into`→`get_performance_monitors` ``，而映射中该字段值是纯枚举 `merge_into`。表中其余 173 行的 `disposition` 单元格都是纯枚举值。 |
| evidence | `TOOL-NAMING.md:223`；生成逻辑在 `docs/scripts/gen_table.py:205-209`（`disp = "`merge_into`→`%s`" % t["merge_target"]`，注释写明是为了「保持 9 列反引号不变式 + 顺带显示存活方」）。我用「整格字符串 == 枚举」的严格谓词扫描时**只有这 1 行不通过**。 |
| location | `docs/TOOL-NAMING.md:223`（`docs/scripts/gen_table.py:205-209`） |
| 影响 | 极小。文档 §4.1 与 §3.0 都另有**专门的 `merge_target` 列**承载同一信息，故此处是**信息重复**而非信息缺失；人读无歧义。仅当消费者用「正则抓第 8 列必须 ∈ 枚举」的脚本解析该 Markdown 表时会漏掉这一行。 |
| recommendation | 二者择一：(a) 生成器改为纯枚举 `` `merge_into` ``，把存活方留在已存在的 `merge_target` 列；(b) 在 §2 表头下加一句 legend 说明该装饰约定。**任一都是 1 行改动，且必须在生成器里改**（手改文档会被下次 `gen_table.py` 覆盖）。 |

### N-2（nit，跨仓库）— 决策日志 D45 的文字滞后于 v1.1 数据

| 字段 | 内容 |
|---|---|
| severity | nit（文档一致性；不影响被验收件） |
| claim | `F:\moonbit-hof-rs\DECISIONS.md:1311` 的 D45 条目写 `mutating` 口径「含游戏/编辑器状态副作用，共 **101** 条」，而 v1.1 映射与 `convention.mutating_semantics` 实际为 **103** 条（101 + D-1 新增的 2 个截图工具）。 |
| evidence | `DECISIONS.md:1311`；映射独立复算 `mutating=true == 103`；`convention.mutating_semantics` 文本含「v1.1 共 103 条」。 |
| location | `F:\moonbit-hof-rs\DECISIONS.md:1311`（不在本仓，且本轮硬性约束为只读） |
| 影响 | 无功能影响。但 D45 是「为什么 v1.1 长这样」的权威来源，101/103 不一致会让后续读者对「本轮到底改动了多少条」产生误判。 |
| recommendation | 由决策者在下一次写 DECISIONS 时补一句「D45 记的 101 为改动前基线，含 D-1 两个截图工具后 v1.1 为 103」。 |

---

## 7. criteria（本次核实项 / 结论 / 方法 / 证据）

| id | 核实项 | 结论 | 方法 | 证据 |
|---|---|---|---|---|
| CR-01 | 三个被验收件指纹 | ✅ 相符 | 自写 sha256 重算 | 70917/`2f552719…`；95060/`96495bad…`；98381/`078b94e5…` |
| CR-02 | `old_name` ↔ 旧契约双向差集 | ✅ 空 | 集合差 | `old-only=[] map-only=[]` |
| CR-03 | 174 条 9 字段完整性/类型 | ✅ | 独立解析 | `bad=[]` |
| CR-04 | L1 正则 + 最长前缀 + verb 闭集 + channel/verb/object 三名一致 | ✅ 0 违规 | 自写解析器（**不复用** `check_rename_map.py`） | `violations=[]` |
| CR-05 | `split('_')[1]` 的反例成立 | ✅ 24/24 | 反例构造 | C3 |
| CR-06 | `disposition` 枚举化、无内嵌写法、`merge_target` 可解析且不越界 | ✅ | 独立解析 | D1–D5 |
| CR-07 | 四组计数（disposition/channel/scope/mutating） | ✅ 与声称全一致（103） | 独立复算 | §2.4 |
| CR-08 | 172 项命名谓词之外的**第 173 条**：`new_name` 尾部 == `object` | ✅ 174/174 | 我额外加的谓词 | C1 |
| CR-09 | 契约 171 条、去重、下架/合并项双向不泄漏、取消合并项各 1 条 | ✅ | 集合运算 | G1–G7 |
| CR-10 | 契约 `description`/`inputSchema` 逐字来自旧契约 | ✅ 171/171，无额外键 | `canonical()` 双向量化比对 | H1/H2 |
| CR-11 | 契约 `_meta` 自洽（5 个 sha/计数/枚举字段） | ✅ | 与真实 sha、映射实况对账 | H3–H9 |
| CR-12 | 契约生成器幂等 + 可逐字节复现落库件 | ✅ | **我跑两次**并比 sha | H10/H11 |
| CR-13 | 文档 174 行**逐字段**对账 | ✅ 174/174，0 不一致 | 自写 Markdown 表解析器 | I1–I4 |
| CR-14 | 文档头部指纹 == 新映射 | ✅ | 字符串包含 + 真实 sha | I5 |
| CR-15 | 文档无 v1.0 残留（3 对合并/169/旧名/内嵌写法/占位名） | ✅ 0 命中 | 正则扫描 | I7–I9 |
| CR-16 | 文档渲染确定 + 逐字节可复现 | ✅ | **沙箱副本**内跑生成器两次 | I10a–I10c、§3.1 |
| CR-17 | 桌面表单元无未登记工具名 token | ✅ 0 | 468 token 白名单比对 | I11 |
| CR-18 | D-1 条件写（字段+reason+convention+**源码事实**） | ✅ | 读 `editor.rs` 原行 | 附录 A |
| CR-19 | D-2/D-3 取消合并（独立性+可区分名字+**差异事实**） | ✅ | 读 `batch.rs`/`analysis.rs`/`project.rs` 原行 | 附录 B |
| CR-20 | D-4/D-5 枚举与口径条款 | ✅ | 字段存在性 + 语义四要素 | 附录 C |
| CR-21 | D-6/D-7/D-8 三处引文 | ✅ 逐字一致 | 读 `.gd`/`project.rs`/`node.rs` 原行 | §1 D-6/7/8 |
| CR-22 | 工程门（39/1465/accept×2） | ✅ 全绿 | 我亲自跑、取退出码 | §5 |
| CR-23 | 自报偏差「逐字门只比 2 个工具」是否准确 | ✅ **准确** | 读 `accept_m1.ps1:60/124-142/593/949` | §5.1 |
| CR-24 | 反例 Top 5 与取消合并的混淆影响 | 见 §4 | 自写相似度启发式 + 逐条选错机制 | §4.1/4.2 |
| CR-25 | 只读纪律（未改任何文件） | ✅ | 三件指纹 + `git status --porcelain` | §3.1、`integrity.py` |

---

## 8. unverifiable（我无法在本轮确证的）

| id | 项 | 为什么无法确证 | 我的处理 |
|---|---|---|---|
| UV-1 | 映射 `reason` 中引用 `godot_mcp_gdext/**` 与 `addons/godot_mcp_rs/**` 的行为，是否等同**未来内置 C++ 模块**（`modules/mcp_server/**`）的对应实现 | 内置模块当前只有 2 个工具（`tools/project.cpp`），171 条里 169 条尚无 C++ 实现可比对。现有引用全是**迁移源**（gdext / gd 插件）的行为，不是目标实现 | 我按「迁移源事实」核验，**全部成立**；目标实现一致性属后续批次门（见 §5.1 建议），本轮 `unconfirmed` |
| UV-2 | `accept_m1.ps1` 的 `case12` 在 game 端点为何 PASS 的确切机制 | 我从 `$ToolNames` 与 `scope=BOTH` 推断出「game 侧也只返回这 2 个 both 工具」，但我没有解包该 case 的 evidence 字符串逐字确认（日志被 `accsum.py` 截断） | 记为**推断**，非证据支持；不影响本轮 verdict |
| UV-3 | 上一轮 v1.0 的**原始**审计报告文件 | `docs/reports/` 下只有 `REPORT-001-rename-map-v1.1.md`（实现方报告），v1.0 的审计报告不在仓内 | 我以任务书 §3.1 + `DECISIONS.md` D45 的缺陷描述为「上一轮缺陷」的权威转述，并**对每条独立读码复核事实**，故不依赖该文件 |
| UV-4 | `convention.verb_closed_set` 37 项是否**上游**认可（D38/D41 只点名 16 个） | 需决策者确认；D45 已把它列为「下一版决定移除或保留并说明」 | 未复现 —— 但 v1.1 已用 `verb_notes` 明确「保留并说明 `evaluate` 用量 0」+「闭集只增不减」，**内部自洽**，记为已知开放项 |

---

## 9. risks（遗留风险，非缺陷）

| id | 风险 | 严重度 | 说明 / 缓解 |
|---|---|---|---|
| R-1 | `editor_list_signal_connections` ↔ `editor_analyze_signal_flow` 仅靠名字不足以可靠二选一 | **中** | 取消合并的正确性毋庸置疑（五项差异经读码确证），但这是本轮**唯一新增**的混淆面：v1.0 调用者只需认识一个名字。缓解：在两者注册时的 `description` 里**内联判别点**（`list`：扁平 `connections[]`+`count`、可按 `signal_name` 过滤；`analyze`：按节点嵌套、只含持久连接、`node_path` 精确）。文档 §3.3 已有该表，建议直接抄进 schema 文案 |
| R-2 | `project_search_file_names` / `project_search_file_contents` 通道/动词/scope/mutating **全同**，名字是唯一判据 | 中 | 缓解：同上，在 `description` 里写明「按文件名子串」vs「逐行内容匹配（上限 50、大小写不敏感）」 |
| R-3 | Top-1 的 `convert_uid_to_path` ↔ `convert_path_to_uid` 是**纯顺序**差异，v1.1 未改且无法靠改名消除 | 中 | 这类「A↔B 反向对」在英文命名里无字形锚点。缓解：`description` 用「源类型 → 目标类型」句式；或在工具列表渲染时按 `object` 字母序并列展示 |
| R-4 | 171 条契约的**全量**逐字对等门尚无脚本承担 | 中 | 批次推进到 B5 前可接受；B5 收口前必须落地（§5.1 建议 2/3）。在此之前「契约全量一致性」只能靠生成器的构造性保证，而不是运行时门 |
| R-5 | 映射 `reason` 的源码引用全部指向**迁移源**（gdext/gd），随内置 C++ 模块重写会**自然过期** | 低 | 现在正确、可复现；建议在每批移植完成时同步刷新该批次条目的引用，或改为指向本模块路径 |
| R-6 | `mutating` 与 hof-rs `is_mutating` 口径不同（103 vs 后者语义） | 低-中 | `convention.mutating_semantics` 已显式禁止直接灌 `MUTATING_EXACT` 并说明 fail-closed 后果。缓解：该禁令需要在 hof-rs 侧有**可执行的**不变式测试（文档 §6 提到 `运行期不变式测试`），本轮无法验证 hof-rs 侧尚未落地 |

---

## 10. next_step_recommendation

1. **接受本轮（v1.1）**：机械层与数据层均 pass，D-1..D-8 8/8 闭合，无新缺陷，工程门全绿。
2. **闭环 2 个 nit（各 1 行，改生成器/决策日志，不改数据）**：
   - N-1：`gen_table.py:205-209` 把 `disposition` 单元格改回纯枚举（或加 legend），**然后重跑生成器**并更新文档头部指纹。
   - N-2：在 hof-rs `DECISIONS.md` D45 补注「101 为改动前基线，v1.1 为 103」。
3. **在下游消费前补足 R-1/R-2/R-3 的 `description` 判别点**：这是「区分度」诉求的最后一公里——名字解决了「不同」，但 `signal_flow/list_connections`、`file_names/file_contents`、`uid_to_path/path_to_uid` 三处仍需一句话才能「不看文档就选对」。
4. **把「171 条全量逐字对等门」显式排进 B5 收口计划**，并在 `accept_m1.ps1` 的 SUMMARY 里把当前 2/171 的已移植率标为 `known_deviation`，避免门被误读为全量（§5.1）。
5. **不要**为了「让门变绿」而提前注册未实现的 169 个工具，也不要提前注册 2 个 `unregister_until_implemented` 与 7 个 `fix_implementation_first`（§4.2/§4.3 已写明硬性要求，其中 `editor_set_tilemap_cell`/`editor_set_tilemap_cells_in_rect` 是数据破坏项，必须先写红测试）。

---

## 附录 A — D-1 证据原文

**A1**（`get_editor_screenshot` → `editor_capture_screenshot`，`mutating=true`）

> 获取编辑器视口（EditorInterface.get_base_control）…闭集动词 capture…属编辑器进程…；但按 **GDR-18 条件写**，`save_path` 非空即把 PNG 落盘写入该路径（editor.rs:327-343），故取最保守语义 `mutating=true`。

**A2**（`get_game_screenshot` → `running_game_capture_screenshot`，`mutating=true`）

> …但按 **GDR-18 条件写**，`save_path` 非空即把 PNG 落盘写入该路径（editor.rs:395-402），故取最保守语义 `mutating=true`。

**A3**（我的源码复核，`godot_mcp_gdext/src/commands/editor.rs:327-343`）

```rust
327|  let save_path = opt_string(args, "save_path", "");
328|  if !save_path.is_empty() {
...
334|      let mut pba = godot::builtin::PackedByteArray::new();
...
339|      let abs_path = ProjectSettings::singleton().globalize_path(&save_path);
340|      let abs_gstr: GString = abs_path.into();
341|      let save_err = img.save_png(&abs_gstr);
342|      if save_err == Error::OK {
343|          data["saved_path"] = serde_json::json!(save_path);
```

**A4**（`:395-402`）

```rust
395|  let save_path = opt_string(args, "save_path", "");
396|  if !save_path.is_empty() {
397|      let abs_path = settings.globalize_path(&save_path);
398|      let abs_gstr: GString = abs_path.into();
399|      let save_err = img.save_png(&abs_gstr);
400|      if save_err != Error::OK { return Err(...); }
403|      return Ok(serde_json::json!({ "saved_path": save_path, ... }));
```

→ **「`save_path` 非空即写 PNG」成立**，D-1 的改动方向正确。

## 附录 B — D-2/D-3 可区分特性的 `reason` 原文 + 源码复核

**B1**（`search_in_files` → `project_search_file_contents`）：递归读取项目文本文件内容逐行匹配（project.rs:194）：返回逐行 `{file,line,text}`、命中上限 50、大小写不敏感；与 `project_find_files_referencing_symbol` 因输出形状/上限/大小写三项不等价，按 GDR-17 不合并。

**B2**（`find_node_references` → `project_find_files_referencing_symbol`）：按文件聚合命中结果 `{file,lines[]}`（batch.rs:496）：与 `project_search_file_contents` 的逐行 `{file,line,text}` 不同，命中上限 100（非 50）、大小写敏感（非不敏感）——三项均有损，按 GDR-17 取消合并并独立保留。

**B3**（`find_signal_connections` → `editor_list_signal_connections`）：返回扁平 `connections[]`+count、收全部连接（不过滤非持久连接）、`node_path` 按子串匹配，并带 `signal_name` 过滤；以上与 `editor_analyze_signal_flow` 不等价，按 GDR-17 取消合并并以 `list_` 独立保留。

**B4**（`analyze_signal_flow` → `editor_analyze_signal_flow`）：按节点嵌套返回、仅保留持久连接（`flags & 1`）、`node_path` 精确匹配、无 `signal_name` 过滤；与 `editor_list_signal_connections` 的形状/过滤/匹配方式不等价，按 GDR-17 取消合并，两者各自保留。

**源码复核结论**：B1–B4 的**每一条**差异断言我都读到了对应源码行，全部成立（详见 §4.3/§4.4 表）。

## 附录 C — D-5 `mutating_semantics` 原文（四要素齐备）

> `mutating` 的口径 = 「是否改变进程/编辑器/游戏状态 **或** 产物」，v1.1 共 **103** 条。它与 hof-rs 的 `is_mutating`（`src/runtime/policy.rs:280`，仅「是否修改产物」）**不是同一谓词**——禁止把本字段直接灌进 `MUTATING_EXACT`：那会把合法取证工具一起拒掉，造成 fail-closed 回归。

---

## 附录 D — 本轮执行的全部命令与临时产物（可复现）

| 用途 | 命令 / 产物 |
|---|---|
| 指纹重算 | `python -c`（hashlib/os），输出见 §2.1 |
| 机械层 | `python %TEMP%\audit001\audit_mech.py` |
| 来源/`_meta`/生成器幂等 | `python %TEMP%\audit001\audit_prov.py`（用 `gen_renamed_contract.py --out %TEMP%\...`） |
| 文档对账/确定性 | `python %TEMP%\audit001\audit_doc.py`、`audit_doc2.py`（沙箱副本 `%TEMP%\audit001\sandbox\`） |
| 混淆度分析 | `python %TEMP%\audit001\confuse.py` → `confuse.txt` |
| 源码抽样 | `python %TEMP%\audit001\excerpts.py` → `excerpts.txt` |
| 只读完整性 | `python %TEMP%\audit001\integrity.py`；`git status --porcelain`（引擎仓 & gdext 仓） |
| MCPServer 门 | `cmd /c "bin\godot.windows.editor.x86_64.console.exe --test --test-case=""[MCPServer]*"" > %TEMP%\audit001\test-mcp.log 2>&1 & echo EXIT=%ERRORLEVEL%"` → EXIT=0 |
| 全引擎门 | `cmd /c "bin\godot.windows.editor.x86_64.console.exe --test > %TEMP%\audit001\test-all.log 2>&1 & echo EXIT=%ERRORLEVEL%"` → EXIT=0 |
| 验收门 ×2 | `cmd /c "chcp 65001 > nul & powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\accept_m1.ps1 > %TEMP%\audit001\accept-run{1,2}.log 2>&1 & echo EXIT=%ERRORLEVEL%"` → 20 PASS / 0 FAIL ×2 |
| 自检脚本交叉对照 | `python modules\mcp_server\docs\scripts\selfcheck.py` → `SELFCHECK result: PASS` |

**只读纪律声明**：验收结束时 `tool-rename-map.json` / `tools_list.renamed.json` / `TOOL-NAMING.md` 三件指纹与开始时**逐字节相同**；引擎仓 `git status --porcelain` 仅列出审计开始前已存在的 4 个未跟踪物（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`）与本任务书自身；gdext 仓 `clean`。全过程**未执行任何 git 写操作**、未安装依赖、未占用 9877（提交前后 PID 36392 均在监听）。
