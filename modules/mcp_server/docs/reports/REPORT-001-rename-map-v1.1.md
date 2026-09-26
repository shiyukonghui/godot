# REPORT-001 — 命名映射 v1.1（修复审计缺陷 D-1..D-8）+ 契约与规范文档重生成

- **status**：`done`（任务书 §3 全部自检项通过；唯一"未做"的是 hof-rs 侧策略改造，按 §4 属于只读范围且已随 D43 暂停）
- **任务书**：`modules/mcp_server/docs/tasks/TASK-001-rename-map-v1.1.md`（v1.1）
- **仓库 / 分支**：`F:\RustProjects\godot-mcp-pro\code\godot`，`feature/mcp-server-module`（**未 push**）
- **报告生成日期**：2026-09
- **本报告的所有命令都在 `code\godot` 下执行**；日志落在 `%TEMP%\task001-*.log`

## commits（英文信息，均未 push）

| sha | 一行说明 |
|---|---|
| `f3a7686939` | `mcp_server: fix the rename map to v1.1 (D-1..D-8) (GDR-17, GDR-18)` |
| `552215dc35` | `mcp_server: regenerate the expected contract from the v1.1 map - 171 tools (GDR-17)` |
| `8400dae1e8` | `mcp_server: commit the TOOL-NAMING generator and re-render the v1.1 spec (GDR-17, GDR-18)` |
| 第 4 个提交 | `mcp_server: add the TASK-001 v1.1 report (D-1..D-8)` — 即本文件自身（自指，故只给提交信息不给 sha） |

```
$ git log --oneline -3
8400dae1e8 mcp_server: commit the TOOL-NAMING generator and re-render the v1.1 spec (GDR-17, GDR-18)
552215dc35 mcp_server: regenerate the expected contract from the v1.1 map - 171 tools (GDR-17)
f3a7686939 mcp_server: fix the rename map to v1.1 (D-1..D-8) (GDR-17, GDR-18)
```

提交后工作树只剩既有未跟踪物（与任务书 §4 要求一致）：

```
$ git status --short
?? .graphifyignore
?? build-m0.cmd
?? graphify-out/
?? install-deps-m0.cmd
```

---

## 1. 环境与只读边界（先证明没越界）

| 约束 | 实测证据 |
|---|---|
| 只改 `modules/mcp_server/**` | `git status --short` 的全部改动都落在 `modules/mcp_server/` 下（见上） |
| 用户 Godot 4.7.1-mono 占用 9877 绝不触碰 | 验收脚本首尾两行：`user editor on 9877 before run: pid=36392` / `listening=True pid_before=36392 pid_after=36392`（两次运行均如此） |
| 测试端口 9888/9889 | `accept_m1.ps1` 内固定（`$EditorPort = 9888` / `$GamePort = 9889`） |
| hof-rs 整个仓库只读 | `git -C F:\moonbit-hof-rs status --short --branch` → `## master`（无任何改动；旧 fixture 只读校验 sha 一致） |
| 未安装依赖、未访问 100.105.152.101:18080 | 本任务只用 Python 3.9.7 标准库 + scons + 仓库内二进制 |
| 未 push | `git log` 只有本地提交；`git status --branch` 仍显示 `## feature/mcp-server-module`（无 upstream ahead 信息） |

被我**只读查阅**（未改）的外部证据：`godot_mcp_gdext/src/commands/*.rs`、
`addons/godot_mcp_rs/mcp_runtime_agent.gd`、`F:\moonbit-hof-rs\tests\fixtures\mcp\tools_list.json`、`F:\moonbit-hof-rs\DECISIONS.md`。

---

## 2. 逐条处置（D-1..D-8，全部来自 D45 / GDR-17 / GDR-18）

### D-1（major，条件写）两个截图工具 `mutating` 改为 `true`

**改了什么**：`get_editor_screenshot`（→ `editor_capture_screenshot`）与 `get_game_screenshot`
（→ `running_game_capture_screenshot`）的 `mutating` 由 `false` 改为 `true`，并在 `reason` 写明触发条件。

**实现侧证据（只读复核，确认"条件写"属实）**：

```
godot_mcp_gdext/src/commands/editor.rs:327-343   (get_editor_screenshot)
  327:    let save_path = opt_string(args, "save_path", "");
  328:    if !save_path.is_empty() {
  ...
  339:        let abs_path = ProjectSettings::singleton().globalize_path(&save_path);
  341:        let save_err = img.save_png(&abs_gstr);
  343:            data["saved_path"] = serde_json::json!(save_path);

godot_mcp_gdext/src/commands/editor.rs:395-402   (get_game_screenshot)
  395:    let save_path = opt_string(args, "save_path", "");
  396:    if !save_path.is_empty() {
  397:        let abs_path = settings.globalize_path(&save_path);
  399:        let save_err = img.save_png(&abs_gstr);
```

**映射侧产物（`docs/tool-rename-map.json` 中该两条）**：

```json
{ "old_name": "get_editor_screenshot", "new_name": "editor_capture_screenshot", "mutating": true,
  "reason": "…但按 GDR-18 记条件写：save_path 非空即把 PNG 真的写到该路径（editor.rs:327-343），故取最保守语义 mutating=true。" }
{ "old_name": "get_game_screenshot", "new_name": "running_game_capture_screenshot", "mutating": true,
  "reason": "…但按 GDR-18 记条件写：save_path 非空即把 PNG 真的写到该路径（editor.rs:395-402），故取最保守语义 mutating=true。" }
```

**计数证据**：`mutating=true` 由 **101 → 103**（见 §4 的 `F3`）。

### D-2（major）取消合并对 1：`search_in_files` ⇄ `find_node_references`

**改了什么**：

| 字段 | v1.0 | v1.1 |
|---|---|---|
| `new_name` | `project_search_file_contents`（与保留方重名） | **`project_find_files_referencing_symbol`** |
| `verb` / `object` | `search` / `file_contents` | **`find` / `files_referencing_symbol`** |
| `disposition` | `merge_into:search_in_files` | **`rename`**（无 `merge_target`） |
| `reason` | "…是重复实现，合并进 search_in_files。" | 写明三项可区分特性（输出形状 / 上限 / 大小写） |

保留方 `project_search_file_contents` 的 `reason` 也补写了同样的三项差异（便于只看名字的人双向选对）。

**实现侧证据（只读复核行号真实）**：

```
godot_mcp_gdext/src/commands/project.rs:194   fn search_in_files_recursive(path, query, file_pattern, matches, max_results)
godot_mcp_gdext/src/commands/batch.rs:496     fn cmd_find_node_references(args)   // 按文件聚合
```

### D-3（major）取消合并对 2：`analyze_signal_flow` ⇄ `find_signal_connections`

| 字段 | v1.0 | v1.1 |
|---|---|---|
| `new_name` | `editor_analyze_signal_flow`（与保留方重名） | **`editor_list_signal_connections`** |
| `verb` / `object` | `analyze` / `signal_flow` | **`list` / `signal_connections`** |
| `disposition` | `merge_into:analyze_signal_flow` | **`rename`**（无 `merge_target`） |

`reason` 写明四项差异（返回形状 / 非持久连接过滤 `flags & 1` / `node_path` 精确 vs 子串 / `signal_name` 过滤），
保留方 `analyze_signal_flow` 的 `reason` 同步写明。

**实现侧证据**：

```
godot_mcp_gdext/src/commands/batch.rs:207      fn cmd_find_signal_connections(args)   // 扁平 connections[] + count
godot_mcp_gdext/src/commands/analysis.rs:387   fn cmd_analyze_signal_flow(args)       // 按节点嵌套
```

> `verb`/`object` 必须随名字一起改，否则注册期 lint（GDR-16 L3）会直接拒绝注册——这也是这两个字段在本次变更中的**唯一**原因，不涉及任何行为改动。

### 唯一保留的合并（GDR-17 判定的无损合并）

`get_editor_performance` → `merge_into` + **`merge_target = get_performance_monitors`**，
`reason` 写明「**代价：返回值由平铺改嵌套**」；保留方 `get_performance_monitors` 的 `reason` 说明自己是保留方且被合并方是真子集。

```
godot_mcp_gdext/src/commands/profiling.rs:32   fn cmd_get_performance_monitors(...)   // 保留方（超集，嵌套形状）
godot_mcp_gdext/src/commands/profiling.rs:63   fn cmd_get_editor_performance(...)    // 被合并方（平铺形状，真子集）
```

### D-4（minor）`disposition` 枚举化 + 独立 `merge_target`

- `disposition` 取值全部落在 `rename | keep | merge_into | unregister_until_implemented | fix_implementation_first`；
- **不存在** `merge_into:<old_name>` 内嵌写法（v1.0 的 3 处已全部消除）；
- `merge_target` **只**出现在唯一一条 `merge_into` 条目上，且指向存在的 `old_name`；
- 新增 `convention.disposition_enum` 声明值域；
- `merge_target` 在条目内的键序紧邻 `disposition`（便于人读）。

**自检输出**：

```
[PASS] E1 disposition values inside the enum                      outside=[]
[PASS] E2 no inline 'merge_into:<old_name>' form                  leftover=[]
[PASS] E3 every merge_into has a resolvable merge_target          targets=['get_performance_monitors']
[PASS] E4 merge_target only on merge_into entries                 stray=[]
```

### D-5（minor）`convention` 块补齐 + `evaluate` 加注

`convention` 由 v1.0 的 4 个键扩充为 11 个键（原 4 个逐字节保留）：

| 新键 | 作用 |
|---|---|
| `verb_notes.evaluate` | **`unused_in_v1`**：v1.1 的 174 项中用量为 0，但作为合法动词保留 |
| `verb_notes_note` | 一句话说明「闭集只增不减」，其余 36 个动词均有实际用量 |
| `disposition_enum` | 值域声明（D-4） |
| `scope_enum` | `editor / game / both` |
| `merge_target_semantics` | 合并项必须带 `merge_target`；取消合并的项不得带 |
| `conditional_write_clause` | GDR-18 保守语义条款 |
| `mutating_semantics` | 口径 = 「状态**或**产物」，**103 条**；与 hof-rs `is_mutating`（`src/runtime/policy.rs:280`，仅「是否修改产物」）**不是同一谓词**；**禁止把本字段直接灌进 `MUTATING_EXACT`**（会误拒合法取证工具，fail-closed 回归） |

**自检输出**：

```
[PASS] F5 'evaluate' kept and annotated unused_in_v1              usage=0 note='unused_in_v1：v1.1 的 174 项中用量为 0，但仍作为合法动词保留在闭集内。'
[PASS] F6 convention carries the D-4/D-5 clauses                  missing=[]
[PASS] F7 convention.disposition_enum == the enum in force        ['rename', 'keep', 'merge_into', 'unregister_until_implemented', 'fix_implementation_first']
[PASS] F8 mutating_semantics states 103 and the policy.rs predicate warning len=177
[PASS] F9 both screenshot tools: mutating=true + conditional-write reason (GDR-18) [('editor_capture_screenshot', True), ('running_game_capture_screenshot', True)]
```

（终端里中文 note 显示为乱码是 PowerShell 控制台编码问题；上面引用的值取自脚本内部的 UTF-8 字符串，文件本身是干净 UTF-8。）

### D-6（nit）`navigate_to` 引文失真

v1.0 reason 凭空引用「请自行实现」（gd 侧并无此文案）。v1.1 换成**逐字实际文案**：

```
$ grep -n "navigate_to|NavigationAgent" addons/godot_mcp_rs/mcp_runtime_agent.gd
550: # 17. navigate_to - 导航到目标（使用导航网格）
553: func _cmd_navigate_to(_params: Dictionary) -> void:
554: 	_write_response({"error": "navigate_to 需要项目中配置 NavigationAgent 和导航网格。请在游戏脚本中使用 NavigationAgent2D/3D 实现移动。"})
```

映射 reason 现引用该文案并标注 `addons/godot_mcp_rs/mcp_runtime_agent.gd:554`。

### D-7（nit）`get_project_info` 误提 `DirAccess`

v1.0 reason 写「（ProjectSettings/DirAccess）」。实际实现：

```
godot_mcp_gdext/src/commands/project.rs:80-97
  81:    let project = ProjectSettings::singleton();
  82:    let editor = EditorInterface::singleton();
  84:    let project_name = get_setting(&project, "application/config/name");
  87:    let screen_size = editor.get_base_control()
  88:        .map(|ctrl| ctrl.get_size())
```

reason 已改为「`ProjectSettings` 的 `application/config/name|version` 与
`EditorInterface.get_base_control().get_size()`，`project.rs:80-97`」，不再提 `DirAccess`。

### D-8（nit）`move_node` 的 `new_name` 重命名副作用

```
godot_mcp_gdext/src/commands/node.rs:296    let new_name = args.get("new_name").and_then(|v| v.as_str());
godot_mcp_gdext/src/commands/node.rs:310-312
  310:    if let Some(name) = new_name {
  311:        node.set_name(name);
  312:    }
```

reason 已补「实现另带可选 `new_name`（`node.rs:296-312`），给了就顺带重命名节点（重命名副作用），故 `mutating=true`」。

### 下游工件重生成（任务书 §2.5）

| 工件 | 处置 |
|---|---|
| `scripts/gen_renamed_contract.py` | 升级到 `GENERATOR_VERSION = "1.1.0"`：读 `disposition` 枚举 + `merge_target`；断言「恰好 2 个下架 + 1 个合并 + 171 条输出」；拒绝内嵌 `merge_into:` 写法；拒绝非合并项携带 `merge_target`；输出统计与 sha256；**idempotent**（连跑两次同 sha） |
| `docs/tools_list.renamed.json` | 重生成：**171 条** = 174 − 2 下架 − 1 无损合并 |
| `docs/TOOL-NAMING.md` | **由生成器重渲染，零手工编辑** |
| 生成器落库 | v1.0 的 `%TEMP%\namdoc\{gen_table.py,template.md,selfcheck.py}`（**确认仍存在**）已收进 `modules/mcp_server/docs/scripts/`，并改写为仓库相对路径 + v1.1 断言；v1.0 硬编码了绝对路径与旧 sha，直接照搬会拒绝运行在 v1.1 映射上，故是**等效重写**而非逐字节拷贝（见 §8 deviations） |
| 一致性自检 | `CONSISTENCY` / `DETERMINISM` 仍为 **PASS**，且证据块内嵌进 §7（见 §6） |

模板中随之更新的章节：§1.2 动词表（`evaluate` 加注）、**§1.5 L6 修正**、§2 表头口径（174 条 / 171 注册 / `mutating` 103）、
§3.0 重名表（3 组 → **1 组**）、§3.2 与 §3.3（取消合并的四项差异表）、§3.4（截图族 GDR-18 条款）、
§4.1 / 新增 §4.1b（唯一合并的代价 + 两对取消合并的差异表）、§5 迁移清单（12 项 → **10 项**，162 → **164**）、
§6.2 / §6.3（`mutating` 宽口径 + 禁止灌 `MUTATING_EXACT` + 动词推 mutating 的 3 处反例）、§7 证据块与 §7.1 说明。

---

## 3. 新指纹（字节数 / sha256，均为真实计算）

| 文件 | 字节 | sha256 |
|---|---|---|
| `docs/tool-rename-map.json` | **70917** | `2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd` |
| `docs/tools_list.renamed.json` | **95060** | `96495badd5abe5670aa075ffe086c3287e7b590fefffdd1d05fdaab974bd50ab` |
| `docs/TOOL-NAMING.md`（869 行） | **98381** | `078b94e546895e8144c75b6aab4ad1be327a706f3c01c382f8f4272d43466631` |

v1.0 对照（任务书 §1 冻结值）：`tool-rename-map.json` 67826 B /
`9f5a57e9201b5f7b0b4929c7562eca3345cc8fa280d63fe1079d4bfae302b91b`；契约 169 条。
旧契约源（只读，未变）：`F:\moonbit-hof-rs\tests\fixtures\mcp\tools_list.json` 48749 B /
`8f8051c4c0f8941089f0b21a193cef7c51fa7c41d7e312b1463ea8593f313c54`（脚本每次运行都重算并断言）。

新增/落库脚本：

| 文件 | 字节 | sha256 |
|---|---|---|
| `docs/scripts/check_rename_map.py` | 12607 | `920152368cdb807caaaaa179c18f589f6f85d8916d622ee092eeae6817571808` |
| `docs/scripts/gen_table.py` | 24681 | `710c4f8c8ad162e27b05734bfc32c17cabcf9dbc029af270cc7c9f886dc724ce` |
| `docs/scripts/selfcheck.py` | 3493 | `79d9a714d13130d5354a721cb8fe51739d87c60a6290a77427fe8b6f07bb11f3` |
| `docs/scripts/template.md` | 48640 | `48737cfd4aa9edd7bb182ef79f61f0e002c6587074da10718315325569a74444` |

---

## 4. 计数断言（真实输出）

`python modules\mcp_server\docs\scripts\check_rename_map.py` —— **自写脚本，未复用 v1.0 的 `check.py` 结论**：

```
MAP      F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\tool-rename-map.json
MAP      bytes=70917 sha256=2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd
MAP      convention_version=1.1

[PASS] A1 total == 174                                            total=174
[PASS] A2 len(tools) == 174                                       len=174
[PASS] B0 old contract sha256 frozen                              8f8051c4c0f8941089f0b21a193cef7c51fa7c41d7e312b1463ea8593f313c54
[PASS] B1 old contract tools == 174                               len=174
[PASS] B2 bidirectional diff empty                                contract-only=[] map-only=[]
[PASS] B3 old_name unique                                         distinct=174
[PASS] E1 disposition values inside the enum                      outside=[]
[PASS] E2 no inline 'merge_into:<old_name>' form                  leftover=[]
[PASS] E3 every merge_into has a resolvable merge_target          targets=['get_performance_monitors']
[PASS] E4 merge_target only on merge_into entries                 stray=[]
[PASS] C1 non-merged new_name globally unique                     duplicates=[]
[PASS] C2 only merge pairs share a new_name                       shared=['editor_get_performance_monitors']
[PASS] D1 L1..L4 over all 174 new_name                            violations=[]
[PASS] D2 naive split('_')[1] demonstrably fails                  24/24 running_game_* misparsed, e.g. running_game_capture_screenshot
[PASS] D3 closed set has 37 verbs                                 distinct=37 listed=37
[PASS] F1 disposition counts 164/7/1/2                            {'rename': 164, 'fix_implementation_first': 7, 'unregister_until_implemented': 2, 'merge_into': 1}
[PASS] F2 channel counts 103/45/24/2                              {'project': 45, 'editor': 103, 'running_game': 24, 'os': 2}
[PASS] F3 mutating true == 103                                    true=103 false=71
[PASS] F4 sum(channel) == 174                                     sum=174
[PASS] F5 'evaluate' kept and annotated unused_in_v1              usage=0 note='unused_in_v1：…'
[PASS] F6 convention carries the D-4/D-5 clauses                  missing=[]
[PASS] F7 convention.disposition_enum == the enum in force        ['rename', 'keep', 'merge_into', 'unregister_until_implemented', 'fix_implementation_first']
[PASS] F8 mutating_semantics states 103 and the policy.rs predicate warning len=177
[PASS] F9 both screenshot tools: mutating=true + conditional-write reason (GDR-18) [('editor_capture_screenshot', True), ('running_game_capture_screenshot', True)]

CONTRACT F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\tools_list.renamed.json
CONTRACT bytes=95060 sha256=96495badd5abe5670aa075ffe086c3287e7b590fefffdd1d05fdaab974bd50ab
[PASS] G1 contract tool count == 171                              len=171
[PASS] G2 contract names unique                                   distinct=171
[PASS] G3 no unregistered/merged-source name leaks into the contract leaked=[]
[PASS] G4 both de-merged pairs present under 4 distinct names     present=['project_find_files_referencing_symbol', 'project_search_file_contents', 'editor_list_signal_connections', 'editor_analyze_signal_flow']
[PASS] G5 contract count == map total - 2 unregister - 1 merge    171 == 171

RESULT: PASS (all checks green)
```

**与任务书 §3.2 的逐项对齐**：

| 断言 | 任务书期望 | 实测 |
|---|---|---|
| `disposition` | rename 164 / fix 7 / merge_into 1 / unregister 2（合 174） | ✅ 一致 |
| `channel` | editor 103 / project 45 / running_game 24 / os 2 | ✅ **未变**（取消合并只是把 2 条 `merge_into` 改成 `rename`，通道与对象仍在同一通道内，故四组计数不动） |
| `mutating=true` | 由 101 → **103**（两个截图工具） | ✅ 103 |
| 契约条数 | **171** | ✅ 171，且无下架/合并目标的多余名（G2/G3） |
| 两个被取消合并的工具 | 各占一条且名字不同 | ✅ `editor_list_signal_connections` 与 `editor_analyze_signal_flow`；`project_find_files_referencing_symbol` 与 `project_search_file_contents`（G4） |

契约生成器的真实输出（**连跑两次，同一 sha，证明 idempotent**）：

```
$ python modules\mcp_server\scripts\gen_renamed_contract.py
gen_renamed_contract: input tools = 174
gen_renamed_contract: output tools = 171
gen_renamed_contract: merged = 1 (get_editor_performance -> get_performance_monitors)
gen_renamed_contract: unregister = 2 (navigate_to, export_project)
gen_renamed_contract: old contract sha256 = 8f8051c4c0f8941089f0b21a193cef7c51fa7c41d7e312b1463ea8593f313c54
gen_renamed_contract: rename map sha256 = 2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd
gen_renamed_contract: output sha256 = 96495badd5abe5670aa075ffe086c3287e7b590fefffdd1d05fdaab974bd50ab
gen_renamed_contract: self-checks = OK (lint 171/171, unique 171/171, disposition enum OK)
gen_renamed_contract: wrote …\docs\tools_list.renamed.json
EXIT=0
（第二次运行：output sha256 完全相同 → idempotent）
```

---

## 5. 构建与测试（真实输出 + 退出码）

### 5.1 构建

```
$ scons platform=windows target=editor tests=yes module_mono_enabled=no -j8
… (ANGLE 未安装的既有 warning，与本任务无关)
Compiling modules\mcp_server\tool_registry.cpp ...
Generating core\version_hash.gen.cpp ...
Linking Static Library bin\obj\modules\module_mcp_server.windows.editor.x86_64.lib ...
Ranlib Library bin\obj\modules\module_mcp_server.windows.editor.x86_64.lib ...
Linking Static Library bin\obj\core\core.windows.editor.x86_64.lib ...
Linking Program bin\godot.windows.editor.x86_64.exe ...
Linking Program bin\godot.windows.editor.x86_64.console.exe ...
scons: done building targets.
INFO: Time elapsed: 00:00:30.97
SCONS_EXIT=0
```

完整日志：`%TEMP%\task001-scons.log`

### 5.2 模块 doctest

```
$ .\bin\godot.windows.editor.x86_64.console.exe --test --test-case=[MCPServer]*
[doctest] test cases:  39 |  39 passed | 0 failed | 1429 skipped
[doctest] assertions: 267 | 267 passed | 0 failed |
[doctest] Status: SUCCESS!
DOCTEST_EXIT=0
```

（stderr 上同步打印的 `ERROR: MCPToolRegistry: tool name 'game_get_x' … (GDR-16 L1)` 等是**负例测试的预期输出**，
分别覆盖 L1 正则、L2 闭集、L4 `update_`、L3 通道/动词声明不一致——它们正是 lint 生效的证据。）

### 5.3 全引擎 doctest（零回归）

```
$ .\bin\godot.windows.editor.x86_64.console.exe --test
[doctest] test cases:   1465 |   1465 passed | 0 failed | 3 skipped
[doctest] assertions: 424548 | 424548 passed | 0 failed |
[doctest] Status: SUCCESS!
FULLTEST_EXIT=0
```

基线 **1465** → 实测 **1465 passed / 0 failed**，无回归。完整日志：`%TEMP%\task001-doctest-all.log`

### 5.4 M1 验收脚本（连跑两次，都要全过）

```
$ powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\accept_m1.ps1
（run #1，日志 %TEMP%\task001-accept-1.log）
user editor on 9877 before run: pid=36392
[PASS] case1_GET_mcp_200
[PASS] case2_initialize
[PASS] case3_tools_list_fixture
[PASS] case4_tools_call_project_info
[PASS] case5_tools_call_invalid_params
[PASS] case6_unknown_method
[PASS] case7_parse_error
[PASS] case8_concurrent_100
[PASS] case9_keep_alive_two_requests
[PASS] case10_half_packet
[PASS] case11_body_too_large
[PASS] case15_connection_reaping
[PASS] case16_expect_100_continue
[PASS] case17_header_too_large_431
[PASS] case18_bare_lf_terminator_400
[PASS] case19_invalid_utf8_body_warns
[PASS] case12_game_process_endpoint
[PASS] case13_game_without_port
[PASS] case14_port_occupied
[PASS] guard_user_port_9877
20/20 cases passed
ACCEPT1_EXIT=0
```

run #1 的 case3 逐字证据（契约条数由 169 变 171 后**仍然成立**）：

```
[PASS] case3_tools_list_fixture
       tools=2; project_get_info: name_verbatim=True inputSchema_verbatim=True description_verbatim=True
       fixture_description='获取项目信息' actual_description='获取项目信息' |
       project_get_settings: name_verbatim=True inputSchema_verbatim=True description_verbatim=True
       fixture_description='获取项目设置' actual_description='获取项目设置'
[PASS] guard_user_port_9877
       listening=True pid_before=36392 pid_after=36392
```

```
（run #2，日志 %TEMP%\task001-accept-2.log）—— 19 个 case + guard 全 PASS，`20/20 cases passed`，ACCEPT2_EXIT=0
```

> 口径说明（写进 §8 deviations）：脚本对等门实际是**按 `$ToolNames`（`project_get_info` / `project_get_settings`）
> 从 `tools_list.renamed.json` 里筛出对应条目做逐字比较**，并非整份契约逐字比较；
> 这两条记录在本任务中未被改动，因此对等门强度不变、且两次均通过。

---

## 6. 文档确定性与一致性（真实输出）

```
$ python modules\mcp_server\docs\scripts\gen_table.py
SOURCE  tool-rename-map.json  bytes=70917  sha256=2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd
LINT    L1..L4 over 174 new_name: 0 violations (longest-prefix parse)
LINT    demonstration: split('_')[1] misparses 24/24 running_game_* names (e.g. running_game_capture_screenshot -> 'game' instead of verb 'capture')
CHANNEL editor=103  running_game=24  project=45  os=2  (sum=174)
DISPO   rename=164  merge_into=1  unregister_until_implemented=2  fix_implementation_first=7
SCOPE   editor=103  both=47  game=24
MUT     mutating=true 103 / false 71
merge_into                   1 项: get_editor_performance
unregister_until_implemented 2 项: navigate_to, export_project
fix_implementation_first     7 项: disconnect_signal, clear_output, set_auto_dismiss, tilemap_set_cell, tilemap_fill_rect, bake_navigation_mesh, get_test_report
MERGE   survivor=get_editor_performance target=get_performance_monitors (shared new_name=editor_get_performance_monitors)
D-1     conditional writes: editor_capture_screenshot / running_game_capture_screenshot both mutating=true (GDR-18)
D-2/D-3 de-merged pairs kept as 4 distinct names: project_search_file_contents, project_find_files_referencing_symbol, editor_analyze_signal_flow, editor_list_signal_connections
D-5     verb_notes.evaluate = 'unused_in_v1：…'
TABLE   rendered rows=174 (assert rows == 174: PASS)
VERBS   closed set=37  used=36  unused=['evaluate'] (annotated unused_in_v1)
VERBS   every example verified against JSON new_name set: PASS
VERBS   one definition per verb: 37/37 distinct definitions
MERGE   duplicate new_name groups=1 (expect 1): editor_get_performance_monitors
GROUPS  §3 消歧分组数 = 11 … 断言 == 11: PASS
CONSISTENCY  channel-prefixed identifiers in doc: 181 distinct (occurrences 336)
CONSISTENCY  ├─ 命中 JSON new_name: 173 个（新名）
CONSISTENCY  ├─ 命中 JSON old_name: 1 个（仅作为「旧名」被引用，属预期）
CONSISTENCY  ├─ 非工具标识符（白名单，通道常量/object 片段）: 7 个 ['editor_add_', 'editor_process', 'editor_set_', 'editor_simulate_', 'project_edit_', 'project_filesystem', 'running_game_assert_']
CONSISTENCY  └─ 无法回查 JSON 的标识符: NONE
CONSISTENCY  result: PASS（文档中出现的工具名 100% 来自 JSON 的 old_name/new_name 集合）
TABLE_FINAL  markdown table data rows containing a 9-column tool row = 174
ASSERT  rows == 174 : PASS
DETERMINISM  render run#1 == render run#2 byte-identical (95702 bytes): PASS
WROTE   …\docs\TOOL-NAMING.md  bytes=98381  sha256=078b94e546895e8144c75b6aab4ad1be327a706f3c01c382f8f4272d43466631  (write-then-read-back byte-identical)
BYTES 98381
SHA256 078b94e546895e8144c75b6aab4ad1be327a706f3c01c382f8f4272d43466631
DETERMINISM PASS
```

**跨进程复跑同哈希**（不清缓存连跑 3 次）：

```
run#2: BYTES 98381 / SHA256 078b94e5…66631 / DETERMINISM PASS
run#3: BYTES 98381 / SHA256 078b94e5…66631 / DETERMINISM PASS
```

`python modules\mcp_server\docs\scripts\selfcheck.py`：

```
BYTES      98381
SHA256     078b94e546895e8144c75b6aab4ad1be327a706f3c01c382f8f4272d43466631
LINES      870          (脚本口径 = \n 计数 + 1；按行读取为 869 行)
MAP_BYTES  70917
MAP_SHA256 2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd
TOOLROWS   174  (assert == 174: PASS)
HEADERS    4 (expect 4)
CH2_COUNTS 2.1=103 2.2=24 2.3=45 2.4=2
PLACEHOLDERS_LEFT 0
MERGE_GROUPS_SECTION OK
HEADER_FINGERPRINT OK      (文档头部内嵌的 map 字节数/sha256 与映射逐位一致)
SECTION7_EVIDENCE EMBEDDED
SELFCHECK  result: PASS
```

> 文档头部指纹由生成器**从映射字节实时计算后回填**，因此不可能与映射漂移；`TOOL-NAMING.md` 不内嵌**自身** sha256（自指无解），
> 改用"两次重渲染逐字节相同 + 写后读回逐字节相同 + 跨进程复跑同哈希"三条可验证事实收口。

---

## 7. 复现指南（全新子代理可直接照抄）

```
cd F:\RustProjects\godot-mcp-pro\code\godot

# 1) 自检（只读）
python modules\mcp_server\docs\scripts\check_rename_map.py            # → RESULT: PASS

# 2) 重新生成契约（idempotent；两次同 sha）
python modules\mcp_server\scripts\gen_renamed_contract.py             # → output tools = 171

# 3) 重新渲染规范文档（确定性）+ 形状自检（只读）
python modules\mcp_server\docs\scripts\gen_table.py                   # → DETERMINISM PASS，sha 078b94e5…
python modules\mcp_server\docs\scripts\selfcheck.py                   # → SELFCHECK result: PASS

# 4) 构建 + 三层测试
scons platform=windows target=editor tests=yes module_mono_enabled=no -j8
bin\godot.windows.editor.x86_64.console.exe --test --test-case=[MCPServer]*
bin\godot.windows.editor.x86_64.console.exe --test
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\accept_m1.ps1   # 连跑两次
```

脚本用到的只读外部输入：`F:\moonbit-hof-rs\tests\fixtures\mcp\tools_list.json`
（sha256 `8f8051c4…3f313c54`，脚本每次运行都重算断言，不写回）。

---

## 8. deviations（与任务书的显式偏离，逐条列明）

| # | 偏离 | 理由 / 影响 |
|---|---|---|
| 1 | **修改了 `docs/DESIGN-DETAIL.md`** 两处（§16 第 4 项、GDR-17 表格行）：把占位名 `project_find_files_containing_pattern` 换成 TASK-001 §2.2 / D45 指定的最终名 **`project_find_files_referencing_symbol`**，并加"初稿占位名"注记 | 任务书未要求改该文件，但它是 `modules/mcp_server/**` 内的规范性文档，且原文本与"映射是唯一事实源"直接冲突；不改会让下一批实现的子代理拿到一个**不存在的名字**。已显式标注来源。**未改**其任何 GDR 结论、计数或执行顺序 |
| 2 | 修改了 `tool_registry.cpp` 的**一行注释**（`169 renamed names` → `171`） | 纯注释、零行为变化；契约条数由 169 变 171 后该注释成为失真引文 |
| 3 | 修改了 `README.md` 一条项目状态 bullet（"3 对 merge" → v1.1 实况 + 171） | 同上，避免文档与事实源冲突 |
| 4 | 除两条**被取消合并**的条目外，还给**两个保留方**（`search_in_files` / `analyze_signal_flow`）补写了同样的可区分特性 | 任务书只要求前者；补后者是为了"只看名字的智能体"从任一侧都能选对（与 GDR-17 的诉求一致），不改变任何字段语义 |
| 5 | map 头部 `convention_version` 1.0→1.1、`generated_for` 改写；新增 `verb_notes` / `verb_notes_note`；`merge_target` 键位放在 `disposition` 之后 | 任务书 §2.3 只要求"加注 `unused_in_v1`"，未规定载体；用 `verb_notes` 承载以免把 `verb_closed_set` 从字符串数组改成对象（会破坏所有既有消费者）。键位重排是为了条目内字段顺序一致 |
| 6 | 新增 `docs/scripts/check_rename_map.py` 并入库 | 任务书 §3.1 要求"自己写"映射自检；入库使其可复现、可被独立验收直接调用（比放在 `%TEMP%` 更符合"证据必须可复现"） |
| 7 | `docs/scripts/{gen_table.py,selfcheck.py}` 是 **v1.1 等效重写**，不是 v1.0 脚本的逐字节拷贝；`template.md` 是 v1.0 模板的原地修订 | v1.0 脚本硬编码绝对路径与**旧** sha/字节数，会 REFUSE 在 v1.1 映射上运行；任务书允许"更新模板中已变化的章节"。已保留 v1.0 的章节结构（1 规范 / 2 对照表 / 3 易混淆消解 / 4 处置清单 / 5 迁移清单 / 6 授权判定重构 / 7 证据）与全部断言风格 |
| 8 | `docs/scripts/template.md` 的 §1.5 **L6 被修正**（v1.0 写"写类动词 ⇒ `mutating=true`"） | 该蕴含被 GDR-18 的条件写直接证伪（`capture_` + `save_path` 仍落盘），D45 也点名动词推 mutating 有 3 处误判。保留原文会让 §1.5 与 §3.4/§6.3 自相矛盾 |
| 9 | §7.1 的"未做的事"里删掉 v1.0 的"没有 `git add/commit/push`"表述 | 本任务**要求**提交（禁止 push），照抄会变成假陈述 |
| 10 | **没有**在 `DECISIONS.md` 追加决策记录 | 任务书 §4 硬性规定"**整个 hof-rs 仓库只读**"，而决策日志位于 `F:\moonbit-hof-rs\DECISIONS.md`。本报告 + 三个提交信息即本任务的决策记录载体（见 §9 建议） |
| 11 | `disposition` 计数断言里的通道计数未变（103/45/24/2） | 这只是**观测结论**而非偏离：任务书 §3.2 已预期"若因取消合并不变则须说明"——取消合并把 2 条 `merge_into` 改成 `rename`，两条工具仍留在原通道内，故四组计数不变 |
| 12 | 验收脚本口径校正 | 任务书 §3.4 说该脚本断言"`tools/list` 与 `tools_list.renamed.json` 逐字相等"；实际实现是按 `$ToolNames` 两个 M1 工具**筛选后**逐字比对。本文按实际口径报告，避免把证据说得比事实强 |

---

## 9. blockers

无。全部 §3 自检项均已真实执行并通过；未遇到环境或网络阻塞（未安装任何依赖）。

需要决策者知晓的**外部**未决项（不阻塞本任务）：
1. `hof-rs` 的 `MUTATING_EXACT` / `TESTER_ALLOW_*` 表驱动改造仍处暂停（D43），本任务按约束未触碰；
2. `godot_mcp_gdext` 与 `addons/**` 仍在用旧名（本任务按约束未触碰），
   `project_find_files_referencing_symbol` / `editor_list_signal_connections` 这两个新名目前**只存在于映射与契约**，
   尚未在 addon 里落地——这是 B 批移植必须原子完成的部分。

---

## 10. next_step_recommendation

1. **可立即进入 B1（42 个工具）**：对等门参照物 `docs/tools_list.renamed.json` 已是最终 **171** 条，
   `CONSISTENCY` / `DETERMINISM` / 映射自检全绿；每批仍走四道门。
2. **建议先做一次"反例复核"再动手改名**：`find_node_references` 与 `find_signal_connections` 的四项差异
   （`batch.rs:207` / `batch.rs:496` / `project.rs:194` / `analysis.rs:387`）在本任务中只做了**行号与函数体锚点**核对
   （见 §2），**没有重跑**这两个工具做行为对照实验；语义差异引自 D45 的审计结论。既然 GDR-17 的裁决完全建立在这四项差异上，
   建议独立验收子代理**直接读这两个函数体**确认（上限 50 vs 100 / 大小写敏感 vs 不敏感 / 扁平 vs 嵌套 / `flags & 1`）。
3. **把 hof-rs 侧的授权判定改造排到解除暂停之后**，并特别注意两点：
   ① 不得把映射的 `mutating`（103 条宽口径）直接灌进 `MUTATING_EXACT`（D-5）；
   ② 动词推 mutating 至少 3 处反例（`convert_` ×2 非写、`open_` 属写）+ 2 处条件写，必须用对象/scope 感知的豁免表。
4. 若决策者希望把本任务的 D-1..D-8 纳入权威决策日志，请在 hof-rs 解除只读约束后补一条
   `D46`（本报告 §2 可直接作为条目正文）；本任务按硬性约束未写。

---

## 11. 交付物清单（本任务全部改动）

| 文件 | 状态 |
|---|---|
| `modules/mcp_server/docs/tool-rename-map.json` | 修改（v1.0 → v1.1，174 条） |
| `modules/mcp_server/docs/tools_list.renamed.json` | 重生成（169 → **171** 条） |
| `modules/mcp_server/docs/TOOL-NAMING.md` | 重渲染（869 行 / 98381 B） |
| `modules/mcp_server/scripts/gen_renamed_contract.py` | 修改（v1.1.0，枚举 + `merge_target`，171 断言） |
| `modules/mcp_server/docs/scripts/check_rename_map.py` | 新增（映射自检 + 计数断言 + 契约断言） |
| `modules/mcp_server/docs/scripts/gen_table.py` | 新增（v1.1 文档生成器，确定性 + 一致性断言） |
| `modules/mcp_server/docs/scripts/template.md` | 新增（v1.1 模板，随生成器一并入库） |
| `modules/mcp_server/docs/scripts/selfcheck.py` | 新增（渲染产物形状/必备内容自检） |
| `modules/mcp_server/docs/DESIGN-DETAIL.md` | 修改（2 处占位名 → 最终名，见 deviations #1） |
| `modules/mcp_server/README.md` | 修改（项目状态 bullet，见 deviations #3） |
| `modules/mcp_server/tool_registry.cpp` | 修改（1 行注释 169 → 171，见 deviations #2） |
| `modules/mcp_server/docs/reports/REPORT-001-rename-map-v1.1.md` | 新增（本文件） |
