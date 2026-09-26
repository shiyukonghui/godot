# REPORT-018 — B3 收官（10 个工具）+ 静默错值修复 + 门脚本去硬编码

- **status**：完成。五道门在冻结提交 `37f8bcb0e1` 上全绿（见 §6）。B3 = **40/40**（见 §5）。
- **commits**（`feature/mcp-server-module`，**未 push**）：
  | sha | 一行说明 |
  |---|---|
  | `2eaa24c9fc` | B3 最后 10 个工具（6 组）+ `coerce_to_property_type` 的 `Variant::can_convert` 门（静默错值 → `-32602`）+ `docs/tool-groups-b3.json` 6 组置 `implemented=true` + `accept_m1.ps1` 的 `$ToolNames` 改为从 manifest 派生 + 证据脚本 |
  | `d856317087` | TASK-018 的 12 个 doctest 用例 + 随已实现并集上移的计数断言 |
  | `37f8bcb0e1` | 修复线上实测发现的**编辑器侧真缺陷**：`editor_execute_gdscript` 编译 `@tool` 脚本（否则 `GDScript::can_instantiate()` 在编辑器运行时恒假） |
  | 本报告 | `docs/reports/REPORT-018-b3-closure.md`（报告提交见 `git log` 最后一条） |
- **本任务基线**：`ddb585d888`（= `scripts/mcp018_b3_closure_evidence.ps1` 的 `$BaseRef`，也是 §2 做派生对照的「上一版」）。
- **门②证据脚本**：`modules/mcp_server/scripts/mcp018_b3_closure_evidence.ps1`（sha256 见 §2.3）。
- **证据落盘**：每次门②运行把**每个请求体与响应体**写到 `%TEMP%\mcp018-evidence\<check_id>.{request,response}.json`（含 `curl.exe -s -o` 抓取的原始字节与 sha256），脚本重跑即可复现。

---

## 1. 第一部分：静默错值（决策者裁决：必须修）

### 1.1 缺陷本体（修前实测）

| 请求（冻结前行为） | 修前响应 | 修后响应 |
|---|---|---|
| `editor_set_node_property {path:"A",property:"position",value:1e20}` | `status: ok`，真正写入 `Vector2(0,0)` | `-32602`，**未写入** |
| `editor_set_node_property_batch {node_type:"Node2D",property:"position",value:1e20}` | `status: ok`，每个匹配节点 `(0,0)` | `-32602`，**任何写入之前**整体拒绝 |
| `editor_add_nodes_batch {nodes:[{type:"Node2D",properties:{position:1e20}}]}` | `status: ok`，节点被创建为 `(0,0)` | `-32602`，未创建任何节点 |
| `running_game_set_node_property {node_path:"A",property:"position",value:1e20}` | `status: ok`，`(0,0)` | `-32602`，未写入 |

根因（引擎事实，不是猜测）：`Variant::operator Vector2()`（`core/variant/variant.cpp:1777-1793`）只有
`VECTOR2/VECTOR2I/VECTOR3/VECTOR3I/VECTOR4/VECTOR4I` 六个分支，`else` 分支返回**默认构造**的
`Vector2()`；`VariantUtilityFunctions::type_convert` 不看引擎自己的转换关系
（`Variant::can_convert`），因此「不兼容」与「不转换」在旧实现里都塌成默认值。同一形状存在于
所有组合型目标（`Vector3`/`Vector2i`/`Rect2`/`Transform2D`/`Color`（来自 FLOAT）/`Array`（来自标量）
…）。

### 1.2 修法（一处定义）

`tools/tool_helpers.cpp` 的 `coerce_to_property_type()` 增加**唯一**一处门：

```cpp
if (!Variant::can_convert(p_value.get_type(), p_target_type)) {
    const Variant would_write = VariantUtilityFunctions::type_convert(p_value, p_target_type);
    r_error = MCPToolError::invalid_params(vformat(
        "Parameter '%s' cannot be written to a %s property: the value is a %s (%s) and this engine's own "
        "conversion relation (Variant::can_convert) does not list %s -> %s, so type_convert would answer %s "
        "instead of the value you sent. …",
        ...));
    return false;
}
```

- 门在 `Object::set()` **之前**，所以「拒绝」天然等价于「没有写入」；
- 消息同时给出**目标类型**、**实参类型/值的 JSON 拼写**、以及**引擎会写成的替代值**（可核对）；
- 引擎自己声明「可转换」的每一对都保留原行为（`FLOAT→INT` 折整与 64 位范围门、
  `INT→FLOAT`、`STRING→COLOR`（`#rrggbb`）、`INT→COLOR`（hex）、`STRING→NODE_PATH`、
  `ARRAY↔PACKED_*`、`VECTOR2I↔VECTOR2`、`NIL→OBJECT` …）。

**批量路径的「任何写入之前」**：`write_node_property` 拆成
`prepare_node_property_value()`（校验：属性存在性 + 声明类型 + 组件映射 + 强制转型）+
`set()` + 读回；`editor_set_node_property_batch` 在写第一个节点之前，对**每个匹配节点**跑
`prepare_node_property_value()`，任一失败即整体拒绝并在消息里加
`Property 'x' write refused before any node was written: …`。

### 1.3 线上证据（读回证明，不是代码审阅）

| check id | 证据 |
|---|---|
| `silent_single_write_refused` | `code=-32602 result_is_null=True`，message 见 §1.2；`sha256=0297a68fca18…4328` |
| `silent_single_read_back_unchanged` | 拒绝后 `A.position = {"x":11.0,"y":12.0}`（正是拒绝前种下的值） |
| `silent_batch_write_refused_before_any_write` | `code=-32602` + `…before any node was written…`；`sha256=1908753531…64d8` |
| `silent_batch_read_back_unchanged` | `A.position={"x":11.0,"y":12.0}`、`Main.position={"x":0.0,"y":0.0}`（两者都没被动过） |
| `silent_disk_read_back_unchanged` | 拒绝后再次 `editor_save_scene`，`scenes/main.tscn` sha256 **前后相同**：`0a0c48b036…e477` |
| `silent_add_nodes_batch_refused` | `code=-32602`、`data.batch.status="rolled_back"`、`data.batch.errors[0].property="position"` |
| `silent_add_nodes_batch_created_nothing` | 拒绝后 `Node2D` 路径仍为 `.`、`A`、`B`（没有 `MCP018Bad`） |
| `silent_game_write_refused` | 9889 上同一条消息、同一 `-32602`（sha256 与 9888 完全一致，两个进程同一实现） |
| `silent_game_read_back_unchanged` | 游戏进程内 `A.position = {"x":3.0,"y":4.0}` 未被改写 |
| `silent_project_setting_refused` | 先建 `mcp018/probe_int`（`type:"int"`，code=0），再送 `1e20` → `-32602`（`outside the range of a 64-bit integer`） |

**回归护栏（合法值仍然写入，逐个读回）**：

| check id | 写入 | 读回 |
|---|---|---|
| `legal_value_vector2_object` | `A.position = {"x":7,"y":8}` | `{"x":7.0,"y":8.0}` |
| `legal_value_vector3_object` | `World.position = {"x":1,"y":2,"z":3}` | `{"x":1.0,"y":2.0,"z":3.0}` |
| `legal_value_float_value` | `A.rotation = 1.5` | `1.5` |
| `legal_value_int_value` | `A.z_index = 3` | `3` |
| `legal_value_color_string` | `A.self_modulate = "#ff0000"` | `{"a":1.0,"b":0.0,"g":0.0,"r":1.0}` |
| `legal_value_string_value` | `Ui.tooltip_text = "mcp018-tooltip"` | `"mcp018-tooltip"` |
| `legal_value_vector2_object_scale` | `B.scale = {"x":2,"y":3}` | `{"x":2.0,"y":3.0}` |
| `silent_vector2_string_form_refused` | `A.position = "Vector2(4, 5)"` | `-32602`（见 §1.5 D-1） |
| `silent_vector2_string_form_kept_value` | 同上（拒绝） | `A.position` 仍是 `{"x":7.0,"y":8.0}` |

### 1.4 **影响面清单**（改变已验收工具的行为，逐条）

| 工具 | 行为变化 | 理由 |
|---|---|---|
| `editor_set_node_property`（B3，TASK-015 已验收） | 布局不兼容的值：`ok` + 默认值 → **`-32602`**，不写入 | 旧行为即静默错值；这是本任务要消除的缺陷类（M2 D-1 同类） |
| `editor_set_node_property_batch`（TASK-017 已验收） | 同上；且失败现在**在循环之前**被捕获（消息带 `before any node was written`） | 保持 TASK-017 的 all-or-nothing 语义 |
| `editor_add_nodes_batch`（TASK-017 已验收） | 元素 `properties` 里的不兼容值：`ok` + 默认值 → `-32602`（`-32602` 属于校验失败，`rolled_back`） | 同上 |
| `running_game_set_node_property`（B2，TASK-012 已验收） | 同上（同一 `write_node_property` 路径） | 同上 |
| `editor_add_resource_to_node_property`、`project_create_resource`、`project_edit_resource`（B1，已验收） | `properties`/`resource_properties` 里布局不兼容的值：`ok` + 默认值 → `-32602` | 同一 `coerce_to_property_type`；越界/不兼容一律 `-32602`（PLAYBOOK §6.2 / TASK-010 口径） |
| `project_set_setting`（本任务新增） | 声明类型无法容纳的值 → `-32602` | 同上 |
| `editor_setup_*`（TASK-017 已验收） | 只写 `float`/资源引用，`can_convert` 均成立 → **无行为变化**（断言未变、门③门④全绿） | — |
| `project_set_node_property_across_scenes`（本任务新增） | 值不兼容 → 整体 `-32000`（plan 阶段拒绝，0 写入） | 同上 |

**为什么「改变已验收行为」在这里是正确的**：旧行为是「报成功却写错值」，正是本项目存在的首要理由
要消除的谎报；契约与 PLAYBOOK 已确立口径为「越界/不兼容一律 `-32602`」。这不是放宽断言，而是把
「成功」的含义收紧到「真的写进去了」。

### 1.5 顺带查出的两个**引擎/既有实现**缺陷（不自行扩大改动范围，报缺陷）

- **D-1（引擎缺陷，本 fork）**：`Variant::construct_from_string()` 是**空壳**——
  `core/variant/variant.cpp:3531-3533` 只有 `r_value = Variant();`，永远返回 NIL。因此
  `property_value_from_json` 里那段「`"Vector2(…)"` 字符串语法」从未生效：值保持 String，
  旧实现再把它 `type_convert` 成**零向量**。TASK-018 之后该拼写被**响亮拒绝**（
  `silent_vector2_string_form_refused`：`String -> Vector2` 不在 `can_convert` 里）。
  **未自行修**：契约（`inputSchema`）没有承诺字符串语法，修它属于新增行为；可工作的向量语法是
  JSON 对象（`{"x":…,"y":…}`，本任务与 TASK-012 的证据都覆盖）。建议决策者决定是否在后续批次
  用 `VariantParser`/`Vector2::from_string` 补上这段语法，或删掉 `property_value_from_json`
  里那段死代码与其注释。
- **D-2（既有实现的消息缺陷）**：`reload() == OK` 但脚本不可实例化时，原逻辑答
  `"does not compile: OK"`（无意义消息）。已在**两个**执行器里拆成两种状态分别作答
  （编译失败给引擎判定；编译成功但不可实例化给明确措辞）。见 §3.1 的 D-4 实测。

---

## 2. 第二部分：门脚本去硬编码

### 2.1 改法

`scripts/accept_m1.ps1` 里的字面量数组（96 个工具名，TASK-014/015/016/017 各手工追加过一次）
换成从 manifest 派生：

```powershell
$ManifestFileNames = @('tool-groups.json','tool-groups-b2.json','tool-groups-b3.json','tool-groups-b4.json','tool-groups-b5.json')
$ToolNames = @()
foreach ($manifestFileName in $ManifestFileNames) {
    $manifestPath = Join-Path $RepoRoot ('modules\mcp_server\docs\' + $manifestFileName)
    if (-not (Test-Path $manifestPath)) { throw … }        # 缺 manifest 必须响亮失败
    $manifestJson = ConvertFrom-Json (Get-Content -Raw -Encoding UTF8 $manifestPath)
    foreach ($manifestGroup in @($manifestJson.groups)) {
        if ($manifestGroup.implemented -ne $true) { continue }
        foreach ($manifestTool in @($manifestGroup.tools)) {
            if ($ToolNames -notcontains $manifestTool) { $ToolNames += [string]$manifestTool }
        }
    }
}
```

**断言未被削弱**：`$EditorToolNames` / `$GameToolNames` / `$EditorOnlyToolNames` /
`$GameOnlyToolNames` 仍由 rename map 的 `scope` 派生；`case3` 仍逐条比较
`name`/`description`/`inputSchema`；`case12` 仍比较游戏端点并断言 editor-only 工具**不在**其中；
`gate_scope_declared` 仍把已实现数与 171 条契约对比。此后新增批次**无需**再改这个脚本。

### 2.2 派生前后逐名 diff（机器输出，取自门②）

```
[PASS] derivation_base_union_equals_base_literal :: base ddb585d888: literal=96 tools, base-manifest union=96 tools, name-by-name diff=[]
[PASS] derivation_new_union_is_old_plus_exactly_ten :: old=96 new=106 removed=[] added_count=10 added_diff=[] added=[editor_execute_gdscript, editor_set_node_script, project_add_autoload, project_convert_path_to_uid, project_convert_uid_to_path, project_create_script, project_edit_script, project_remove_autoload, project_set_node_property_across_scenes, project_set_setting]
[PASS] derivation_new_script_has_no_tool_literals :: new script quoted tool names=0; old script quoted tool names=96 (old literal size=96); new sha256=8d89a02bab8ea0a5f2bd92db616d3bde3502cfc46375b7ad57fdfc5b49a006d2
```

读法：「上一版硬编码清单」=**从 `git show ddb585d888:` 取出的脚本原文**（不是抄进证据脚本的副本）；
用同一派生规则跑 `git show ddb585d888:` 取出的 manifest，得到**同样是 96 个**，逐名
`Compare-Object` 结果为空 ⇒ 派生规则与旧硬编码清单**完全一致**。再把同一规则应用到工作树 manifest，
得到 106 个，差集**恰好是**本任务的 10 个工具、删除集为空。最后：新版脚本里「引号包起来的工具名」
计数为 **0**（旧版为 96），即字面量清单已被真正移除。

### 2.3 相关文件 sha256（冻结提交）

| 文件 | sha256 |
|---|---|
| `scripts/accept_m1.ps1` | `8d89a02bab8ea0a5f2bd92db616d3bde3502cfc46375b7ad57fdfc5b49a006d2` |
| `docs/tool-groups-b3.json` | 见 `git show 37f8bcb0e1:…` 与 §7 说明（manifest 只把 6 个 `implemented` 由 `false` 改为 `true`，未动任何工具名/组名） |

---

## 3. 第三部分：B3 最后 10 个工具（6 组）

### 3.1 逐工具表

> `channel`/`verb`/`scope`/`mutating` 全部来自 `docs/tool-rename-map.json`；`description` 与
> `inputSchema` 逐字取自 `docs/tools_list.renamed.json`（用 `JSON` 解析字面量注册，避免手写漂移）。
> 8 个 `project_*` 为 `scope=both`（两端点都可见），2 个 `editor_*` 为 `scope=editor`（9889 缺席）。

| new_name | 迁移源位置 | 可观察契约（参数 / 返回形状 / 上限 / 错误） | C++ 落点 | 与迁移源的差异 |
|---|---|---|---|---|
| `editor_execute_gdscript` | `addons/godot_mcp/commands/editor_commands.gd:353-412`（`execute_editor_script`），`editor.rs:353` | `code`（string，必填、去空白非空、**≤249 KiB UTF-8**）是 GDScript **函数体**；真编译（`GDScript` + `reload()`，非 `Expression`）；返回 `{"result":<serialize_variant>,"result_type":"<Variant 类型名>"}`；空体 → `result:null/result_type:"Nil"`；不编译 → `-32602`（`does not compile: <verdict>`）；无脚本语言 → `-32000`；无 GDScript 模块 → `-32000`；超限 → `-32602`（含字节数与上限）；`Callable` 调用失败 → `-32603` | `tools/editor_script_write.cpp`；源码构造共用 `MCPTools::build_execute_gdscript_source(code, /*tool=*/true, …)` | **机制替换**：迁移源用 `Expression`（只能一条表达式）→ 真编译函数体；返回值由 `str(output)` → 结构化 `{result,result_type}`；`-32002` → `-32602`；**保留** `@tool` 语义（新生成的脚本带 `@tool`，见 D-4）。**有意不保留** `allow_unsafe_editor_io` 文本黑名单（可被 `FileAccess`+拼接绕过、且契约无此参数）与 `_mcp_print` 输出捕获（`print()` 仍进引擎日志） |
| `editor_set_node_script` | `script_commands.gd:282-320`（`attach_script`），`script.rs:282` | `node_path`+`script_path`（都必填非空）；节点用模块统一 `find_node` 解析；`script_path` 规范化且必须存在（否则 `-32001`）；不是 `Script` → `-32602`；加载失败 → `-32000`；返回 `{"node_path","script_path"（写后读回的实际路径）,"attached":true,"previous_script_path"}`；非编辑器进程 → `-32000` | `tools/editor_script_write.cpp` | 迁移源答常量 `{"attached":true}` 并只登记 UndoRedo（未执行）；本实现写后**读回**再答；**未复刻 UndoRedo 包装**（B3 编辑器写组一律直接改 live 场景，单点特殊化会破坏一致性） |
| `project_create_script` | `script_commands.gd:105-156`（`create_script`），`script.rs:105` | `path`（必填，`res://`，扩展名 `.gd`/`.cs` 大小写不敏感）、`content`（可选）、`template`（可选，默认 `"Node"`，作为基类）；无 `content` 时生成迁移源的模板体（含末尾换行）；**原子发布**，失败不破坏原文件；返回 `{"path","created","existed_before","bytes","template","editor_rescan_triggered"}`；扩展名错/基类不是合法标识符 → `-32602` | `tools/project_script_write.cpp`（`_text_writer` + `publish_file_atomically`） | 参数集按**重命名契约**（`content`+`template`）而非迁移源的 `extends`/`class_name`/`force`；覆盖已存在文件时**显式报告** `existed_before:true`；`bytes` 是 **UTF-8 字节数**（PLAYBOOK §6.9）且从**落盘文件**量取 |
| `project_edit_script` | `script_commands.gd:159-250`（`edit_script`），`script.rs:159` | `path`（必填、必须存在）；**恰好一种模式**：`content`（整体替换）或 `search`（非空）+`replace`（可选，默认空串，替换**全部**出现）；两种同时给 / 都不给 → `-32602`；`search` 未命中 → `-32001`（**不写入**）；返回 `{"path","changes_made","mode","replacements","bytes","editor_rescan_triggered"}` | `tools/project_script_write.cpp` | 迁移源的 `replacements` 数组 / `start_line` / `end_line` / `insert_at_line` 不在重命名 schema 内，故不接受；`search` 未命中由迁移源的 `{"changes_made":0}` 成功改为 `-32001`（要求没发生的事不得报成功）；原子发布取代直接写 |
| `project_add_autoload` | `project_commands.gd:335-367`（`add_autoload`） | `name`（必填、单个合法标识符）、`path`（必填、`res://`、必须存在）；键 `autoload/<name>`，值 `"*"+path`；**幂等**：同值再注册 → 成功 + `already_present:true`（不写盘）；不同值 → `-32000` + `data.current_value/requested_value/suggestion`；文件不存在 → `-32001`；返回 `{"name","path","key","setting_value","added"}`；`project.godot` **原子发布** | `tools/project_autoload_write.cpp` + `MCPTools::publish_project_settings()` | 迁移源的「已存在」一律 `-32000` → 拆成「同值幂等成功 / 不同值拒绝」两类；新增 name 合法性校验（迁移源没有，`name` 含 `/` 会写出畸形 `project.godot`）；写失败会把内存值回滚，磁盘仍是旧字节 |
| `project_remove_autoload` | `project_commands.gd:370-390` | `name`（必填、合法标识符）；未声明该 autoload → `-32001` + suggestion；成功 → `{"name","key","old_path","removed":true}`；原子发布 | `tools/project_autoload_write.cpp` | 与迁移源一致（含「不存在即报错」）；差别只在原子发布与回滚 |
| `project_set_setting` | `project_commands.gd:173-212`（`set_project_setting`） | `key`（必填非空）、`value`（**必填，任意 JSON**）、`type`（可选，合法类型名）；已有键按**声明类型**强制转型（`int` 折整、`Vector2` 收对象/组件、`Color` 收 `#rrggbb`），`type` 与声明类型不符 → `-32602`；不存在的键：允许创建但报 `existed_before:false`/`created:true`，值 `null` → `-32602`；返回 `{"key","value"（读回）,"type","existed_before","created","saved"}`；原子发布 + 失败回滚 | `tools/project_setting_write.cpp` | 类型表显式列出（拒绝 `Object` 等不可写类型）；**不再**用 `Expression` 解析字符串（迁移源把 `"1e20"` 静默变成别的值）；`null` 新键被拒；新增 `created` 报告（迁移源无法告诉调用者「你刚发明了一个没人读的键」） |
| `project_set_node_property_across_scenes` | `batch_commands.gd:257-369`（`cross_scene_set_property`）+ `372-391`（`_collect_scene_files`）+ `394-404`（`_cross_scene_collect_changes`） | `type`（必填，必须是存在的 `Node` 子类，否则 `-32602`）、`property`（必填非空）、`value`（必填，任意 JSON）、`path_filter`（可选，默认 `res://`）、`exclude_addons`（可选，默认 true）、`force`（可选，默认 false）、`dry_run`（可选，**默认 `not force`**）；**两阶段 all-or-nothing**：plan 阶段逐场景逐节点校验（不写任何字节），commit 阶段逐文件原子发布且失败时用**原始字节**整体回滚；返回 `{"type","property","dry_run","force","path_filter","scenes_affected"[{scene,nodes,count,mode}],"skipped_open_scenes","errors","total_scenes","total_nodes","editor_rescan_triggered","message"}`，`mode ∈ {dry_run, offline_saved, live_open_scene}` | `tools/project_cross_scene_write.cpp` | ①匹配节点**缺该属性** → 整体拒绝（迁移源静默跳过，`if property in node`）；②场景**加载失败** → 报错并整体拒绝（迁移源 `continue` 后报成功）；③跨文件回滚（迁移源直接 `ResourceSaver.save` 覆盖）；④`type` 不是类 → `-32602`（迁移源回答 `total_nodes:0` 成功）；⑤场景文件列表**排序**（PLAYBOOK §6.8 确定序）；⑥节点路径自行沿父链计算（`Node::get_path_to()` 对未挂树的实例返回空路径，迁移源与「先写盘再打包」的早期设计都会得到空 `nodes`） |
| `project_convert_path_to_uid` | `project_commands.gd:233-247`（`project_path_to_uid`） | `path`（必填、`res://`、必须存在否则 `-32001`）；返回 `{"path":<规范化>,"uid":<text 或 "">}`；**路径存在但未注册 UID → 空串成功，不报错**（契约明文）；非项目路径 → `-32602` | `tools/project_resource_uid_read.cpp`（`ResourceLoader::get_resource_uid`） | 迁移源对「无 UID」答 `-32001`；重命名契约明文规定为空串成功 ⇒ **契约优先** |
| `project_convert_uid_to_path` | `project_commands.gd:215-230`（`uid_to_project_path`） | `uid`（必填、`uid://<小写 base36>`）；格式非法（含 `res://` 路径、大写、裸数字）→ `-32602`；格式合法但未注册 → `-32001`；成功 → `{"uid":<原样回显>,"path":<注册路径>}` | `tools/project_resource_uid_read.cpp`（`ResourceUID::text_to_id/has_id/get_id_path`） | 与迁移源一致（含「格式非法 → 参数错误」） |

### 3.2 三类证据（门②，每个工具成功 / 缺参 / 底层失败各至少一条）

| 工具 | 成功 | 缺参 `-32602` | 底层失败 |
|---|---|---|---|
| `editor_execute_gdscript` | `{"result":6,"result_type":"int"}`（循环体）；`{"result":42,…}`（提升的 `func`） | `Missing required parameter: code` | 不编译 → `-32602 does not compile: Parse error`；超限 → `-32602 …302409 bytes, above the 254976 byte limit…` |
| `editor_set_node_script` | `{"attached":true,"node_path":"A","previous_script_path":"","script_path":"res://scripts/attached.gd"}` | `Missing required parameter: script_path` | 脚本不存在 → `-32001`；节点不存在 → `-32001` |
| `project_create_script` | `{"bytes":44,"created":true,"existed_before":false,"path":"res://scripts/templated.gd","template":"Node"}` + 读回模板逐字相等 | `Missing required parameter: path` | 扩展名错 → `-32602 …(.gd or .cs)…`；`template:""` 且无 `content` → `-32602` |
| `project_edit_script` | `mode:"content"` / `mode:"search_replace", replacements:1` + `project_read_script` 读回 | `Missing required mode: …` | 文件不存在 → `-32001`；`search` 未命中 → `-32001` 且**文件 sha256 前后相同**；两种模式同时 → `-32602` |
| `project_add_autoload` | `{"added":true,"key":"autoload/Mcp018One","setting_value":"*res://scripts/one.gd"}` + `project_get_settings prefix=autoload/` 读回 + `project.godot` 内容含该行 | `Missing required parameter: name` | 文件不存在 → `-32001`；同名不同值 → `-32000` + `data.current_value` |
| `project_remove_autoload` | `{"key":"autoload/Mcp018One","old_path":"*res://scripts/one.gd","removed":true}` + 读回 `{"count":0}` | `Missing required parameter: name` | 未声明 → `-32001` |
| `project_set_setting` | `{"created":true,"type":"Vector2","value":{"x":10.0,"y":20.0}}` + `project_get_settings` 读回同形 | `Missing required parameter 'value'` | 类型名未知 → `-32602`；与声明类型不符 → `-32602`；值不可容纳 → `-32602`；新键 `null` → `-32602` |
| `project_set_node_property_across_scenes` | `{"dry_run":false,"total_scenes":2,"total_nodes":3,"scenes_affected":[…offline_saved…]}` + 落盘 `rotation = 0.75` + `project_read_scene_file_content` 读回 | `-32602 Parameter 'value'`（缺 `value`） | **故意坏的中间文件** → `-32000 Refusing to write…` 且 `data.scenes.scenes_named=[res://cross/two.tscn]`、两个 `.tscn` sha256 **前后完全相同**；值不可容纳 → `-32000`（`errors=2`）且 0 写入；`type` 不是类 → `-32602` |
| `project_convert_path_to_uid` | `{"path":"res://scripts/one.gd","uid":"uid://ctls5mw66gfxo"}`（`--import` 生成的 `.uid` 已被解析） | `-32602 Missing required parameter: path`（用 `{"uid":…}` 调它时正是这条） | 文件不存在 → `-32001`；非项目路径/传 `uid://…` → `-32602` |
| `project_convert_uid_to_path` | `{"path":"res://scenes/main.tscn","uid":"uid://6n72"}`（脚本内 `ResourceUID.add_id` 种入后由工具解析） | `Missing required parameter: uid` | `"res://…"` / `"uid://UPPER"` → `-32602`；未注册 → `-32001` |

**不可构造类的声明**：无。10 个工具的「成功 / 缺参 / 底层失败」三类在本机上都可构造并已取到真实响应
（证据文件在 `%TEMP%\mcp018-evidence\`，脚本可重跑复现）。

### 3.3 跨工具端到端活证据链（每组至少一条）

1. **editor_script_write**：`project_create_script`（写 `res://scripts/attached.gd`）→
   `editor_set_node_script`（挂到 `A`）→ `editor_execute_gdscript` **读回**
   `A.get_script().resource_path` = `"res://scripts/attached.gd"`
   （`editor_set_node_script_read_back_chain`）。单工具证据抓不到「写成功但没挂上」，这条抓到了。
2. **project_script_write**：`project_create_script`（模板）→ `project_read_script`（读回模板逐字）
   → `project_edit_script`（search/replace）→ `project_read_script`（读回 `renamed_marker`）
   → 未命中 search 时 sha256 不变。
3. **project_autoload_write**：`project_add_autoload` → `project_get_settings prefix=autoload/`（读回）
   → `project.godot` sha256 变化且内容含 `Mcp018One="*res://scripts/one.gd"` → 重复添加（幂等，不写盘）
   → `project_remove_autoload` → `project_get_settings`（`count:0`）。
4. **project_setting_write**：`project_set_setting(type:"Vector2", value:{"x":10,"y":20})`
   → `project_get_settings prefix=mcp018/` 读回 `{"mcp018/probe_vec":{"x":10.0,"y":20.0}}`
   （**类型保真**：不是字符串、不是零向量）。
5. **project_cross_scene_write**：dry-run（0 写入）→ 坏中间文件反例（0 写入）→ commit（两场景落盘）
   → `project_read_scene_file_content` 读回 `rotation = 0.75`。
6. **project_resource_uid_read**：`project_convert_path_to_uid` 得到 `uid://ctls5mw66gfxo`
   → `project_convert_uid_to_path` 回得 `res://scripts/one.gd`（**双向往返一致**）。

### 3.4 UID 两个方向的二选一（任务书 ⑤）

**「按契约描述能否可靠二选一」——能，且有三重独立判别点**（契约原文即判别点）：

| 判别点 | `project_convert_path_to_uid` | `project_convert_uid_to_path` |
|---|---|---|
| 参数名（schema 唯一属性） | `path` | `uid` |
| 契约描述里的判别句 | 「入参为项目路径（如 res://...），返回 {path,uid}，路径未注册时 uid 为空串且不报错」 | 「入参为字符串文本 UID（如 uid://...），返回 {uid,path}，UID 文本格式非法时报参数错误」 |
| 参数**形状**（实现强制） | 非 `res://` 前缀 → `-32602`；不存在 → `-32001` | 非 `uid://<小写 base36>` → `-32602`；未注册 → `-32001` |

**「方向搞反会静默返回错映射」的对照**：一个把方向实现反了的版本，最可能的形态是**回显**——
`uid_to_path` 直接把入参放到 `path` 键下，于是得到
`{"uid":"uid://ctls5mw66gfxo","path":"uid://ctls5mw66gfxo"}`：字段名齐全、JSON 合法、`status: ok`，
但 `path` 根本不是 `res://` 路径。这类错映射**可被机器检测**，本任务把两条规则做成断言：

```
[PASS] uid_direction_rules_machine_checked :: path_to_uid: uid field is a uid or empty=True (value 'uid://ctls5mw66gfxo');
       uid_to_path: path field starts with res://=True (value 'res://scenes/main.tscn')
```

即：`path_to_uid` 的 `uid` 字段只能是 `uid://…` 或空串，`uid_to_path` 的 `path` 字段只能以
`res://` 开头。加上把**反方向**输入喂进每个工具时的**响亮失败**：

```
[PASS] uid_uid_to_path_rejects_a_path_32602 :: code=-32602 message='Parameter 'uid' is not a valid UID text: 'res://scripts/one.gd' …'
[PASS] uid_path_to_uid_rejects_a_uid_32602 :: code=-32602 message='Parameter 'path' must address the project ('res://...'), got 'uid://6n72''
[PASS] uid_argument_names_are_the_discriminator :: project_convert_path_to_uid with {'uid': …} -> code=-32602 message='Missing required parameter: path'
```

三条一起：**契约文字能可靠二选一**（参数名是不同且唯一的）、**方向反了会响亮失败**（不会静默给错映射）、
**万一真给错映射也有机器规则能抓住**（两个 `starts with` 断言）。

### 3.5 本任务发现并修复的编辑器侧真缺陷（D-4，线上实测）

首轮门②（77/102）测出：**9888 上每一个 `editor_execute_gdscript` 调用都返回
`-32602 "does not compile: OK"`**。`"OK"` 说明 `reload()` 成功——即脚本**编译通过但无法实例化**。
根因是引擎自己的判据：

```cpp
bool GDScript::can_instantiate() const {
    return valid && (is_tool() || !Engine::get_singleton()->is_editor_hint());
}
```

编辑器进程里「非 `@tool` 脚本」不可实例化。修法：`build_execute_gdscript_source()` 增加显式
`p_tool_script` 参数，编辑器执行器传 `true`（生成 `@tool\nextends RefCounted`），游戏执行器继续传
`false`（生成的源码与 TASK-010 钉住的逐字节相同）。同时把「编译失败」与「编译成功但不可实例化」
两种状态**分开作答**（两个执行器都改了），`does not compile: OK` 不会再出现。修后：

```
[PASS] editor_execute_gdscript_success :: payload={"result":6,"result_type":"int"}
[PASS] editor_execute_gdscript_lifted_helper_func :: payload={"result":42,"result_type":"int"}
[PASS] editor_execute_gdscript_compile_error_32602 :: code=-32602 message='Parameter 'code' does not compile: Parse error'
```

---

## 4. 红 / 绿证据（doctest 真实输出）

**红阶段 1（实现前，最终测试已就位）**：`--headless --test --test-case="[MCPServer]*"`

```
[doctest] test cases:  168 |  150 passed | 18 failed | 1429 skipped
[doctest] assertions: 6603 | 6542 passed | 61 failed |
[doctest] Status: FAILURE!   (exit 1)
```

其中**真正的红**是两处被钉住的旧行为（实现前必然失败）：
`test_mcp_server.h(5985)`（TASK-012 用例里 `coerce_to_property_type(Dictionary, VECTOR2)` 断言成功并得零向量）
与 `test_mcp_server.h(9740)`（`"Vector2(4, 5)"` 字符串形式旧实现「成功」）。
其余 16 个用例/59 条断言是**我自己的测试期望错**（计数断言随已实现并集上移、`result_type` 是 `"Nil"`、
`-contains` 在 PowerShell 里是集合运算符、`MCPToolRegistry::call_tool` 成功时不重置 `caller` 的
`r_error` 等），已在同一轮修掉并在提交信息里记录。

**红阶段 2（@tool 缺陷，线上）**：门②首轮 `77/102 checks passed`，其中
`editor_execute_gdscript_success / _lifted_helper_func / _resource_bound` 与 `uid_seed` 全部
`payload` 为空，响应体为 `-32602 "does not compile: OK"`（证据见 §3.5）。

**绿阶段（冻结提交 `37f8bcb0e1`）**：

```
[doctest] test cases:  168 |  168 passed | 0 failed | 1429 skipped
[doctest] assertions: 6610 | 6610 passed | 0 failed |
[doctest] Status: SUCCESS!   (exit 0)
```

**既有计数断言的上移**（已实现并集 96 → 106 的必然结果，不含新语义）：
`get_tool_count() 96→106`、`get_visible_tool_count(true) 79→89`、
`get_visible_tool_count(false) 40→48`、`get_visible_tool_count(true)(游戏进程) 23→31`、
`game_list.size() 40→48`、`editor_list.size() 79→89`、`build_tools_list(true).size() 23→31`。

---

## 5. B3 收官 40/40（机器校验输出）

```
[PASS] b3_is_complete_40_40 :: manifest total=40 tools=40 groups=12 implemented_tools=40 implemented_groups=12
[PASS] b3_live_40_40_on_9888 :: B3 tools live on 9888: 40/40 (editor endpoint serves editor+both)
[PASS] b3_live_on_9889_matches_scope :: B3 tools with scope<>editor: 8, live on 9889: 8; B3 editor-scope tools: 32 (none of them live on 9889: [])
[PASS] b3_check_tool_groups_python :: --batch B3 exit=0 --check-completeness exit=0; last line: TOOL-GROUPS-B3 CHECK PASS
```

- manifest：`docs/tool-groups-b3.json` `total=40`、12 组、`implemented=true` 12 组、工具 40 个；
- **线上 40/40**：9888 端点逐个出现；9889 端点按 rename map 的 `scope` 期望 8 个、实到 8 个，
  32 个 editor-scope 工具**一个都没漏进** 9889；
- `docs/scripts/check_tool_groups.py --batch B3` 与 `--check-completeness` 退出码均为 0
  （后者证明 B3/B4/B5 三分区仍然恰好覆盖未实现的 105 条契约项：B3=40、B4=7、B5=58）。
- 收口后 `accept_m1.ps1` 的汇总：`implemented tools = 89 (editor endpoint) / 48 (game endpoint); contract = 171`。

---

## 6. 五道门（冻结提交 `37f8bcb0e1`，真实输出与退出码）

**第 0 步（版本绑定，PLAYBOOK §3 的 R-1）**：

```
engine --version : 4.8.dev.custom_build.37f8bcb0e
git rev-parse --short HEAD : 37f8bcb0e1     ⇐ 一致
[PASS] gate_version_matches_head :: engine='4.8.dev.custom_build.37f8bcb0e' head='37f8bcb0e1'
```

| 门 | 命令 | 结果 | exit |
|---|---|---|---|
| ① 契约子集逐字（6 组各一次） | `scripts\check_contract_subset.ps1 -Group <g>` | `editor_script_write`/`project_script_write`/`project_autoload_write`/`project_setting_write`/`project_cross_scene_write`/`project_resource_uid_read` 各 **3/3 checks passed**；每组：本组工具在 9888 与 9889 上 `name=True description=True inputSchema=True`（editor 组在 9889 为 `correctly absent`）；`implemented_union=89 tools (editor endpoint) / 48 tools (game endpoint)`；`guard_user_port_9877` PASS | 0 ×6 |
| ② 三类证据 + scope + 链 + 事务反例 + 派生对照 + B3 校验 | `scripts\mcp018_b3_closure_evidence.ps1` | **`104/104 checks passed`** | 0 |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | `168/168` 用例、`6610/6610` 断言、0 failed、1429 skipped | 0 |
| ④ 全引擎回归（仓库根） | `--headless --test` | `1594/1594` 用例、`430892/430892` 断言、0 failed、3 skipped（基线 1583/430157 ⇒ 只增） | 0 |
| ⑤ 批量收口（连跑两次） | `scripts\accept_m1.ps1` | **`22/22 cases passed` ×2**；两次 PASS 清单 `Compare-Object` **diff count = 0**；两次汇总均 `implemented tools = 89 … / 48 …; contract = 171` | 0, 0 |

门②的附加项（任务书 §4 要求）：§1 的**前后对照与「未被改动」证明**（`silent_*` 全组，含磁盘 sha256
前后相同）、§2 的**派生等价证明**（`derivation_*`）、§3 的**多场景事务反例**
（`across_scenes_broken_middle_file_refused` + `_wrote_nothing`）与 **UID 方向对照**
（`uid_direction_rules_machine_checked` + 两个反方向 `-32602`）——全部 PASS。

日志（本地 `%TEMP%`，脚本可复现）：
`mcp018_final_gate2.log`、`mcp018_final_gate3.log`、`mcp018_final_gate4.log`、
`mcp018_final_gate1_<group>.log` ×6、`mcp018_final_gate5_runA.log` / `runB.log`。

---

## 7. 实施者自行决策的事项（若有）+ 待决策者批准项

自行决策（都在代码注释与本报告里写明理由）：

1. `editor_execute_gdscript` **不复刻**迁移源的 `allow_unsafe_editor_io` 文本黑名单（契约无此参数，
   且字符串黑名单不是沙箱）；`print()` 输出不进返回值（无 `_mcp_print` 捕获）。
2. `editor_execute_gdscript` 的**资源边界**取「入参 ≤249 KiB UTF-8」：代码在主线程同帧同步执行，
   装不了超时（GDScript 需要场景树，不能挪线程），这是能诚实强制的那一个界；超限 `-32602` 并给出
   字节数与上限。
3. `editor_execute_gdscript` 不调用 `require_editor_ui()`：它自己不访问 `EditorInterface`/`EditorNode`，
   加上运行期守卫只会拒绝合法的无头编辑器请求；工具本身 `scope=editor`，游戏中**根本不注册**
   （门①已证明 9889 缺席 + `-32601`）。
4. `editor_set_node_script` **不复刻** UndoRedo 包装（B3 编辑器写组一律直接改 live 场景）；
   改为写后**读回**再作答。
5. `project_create_script` 允许覆盖已存在文件（迁移源行为），但**显式回报** `existed_before`。
6. `project_edit_script`：`content` 与 `search`/`replace` 是**互斥模式**，同时给或都不给 → `-32602`
   （猜测调用者意图 = 把「查找替换」变成「整文件覆盖」的经典事故）；`search` 未命中 → `-32001`。
7. `project_add_autoload`：同值重复 → 幂等**成功** + `already_present:true`；不同值 → `-32000`
   （对齐 `editor_connect_signal` 的先例）；`project_remove_autoload` 对不存在的名字 → `-32001`
   （对齐 `editor_disconnect_signal`）。
8. `project_set_setting`：允许创建不存在的键，但**报告** `created:true`；新键 `null` 值 → `-32602`；
   `type` 参数只在键不存在时用于声明类型，键存在时与声明类型**校验**（不符 `-32602`）。
9. `project_set_node_property_across_scenes`：**all-or-nothing 两阶段** + 跨文件字节级回滚；
   坏场景/缺属性/值不兼容 → 整体拒绝（不做「跳过后报成功」）。
10. 排序：场景文件列表排序（确定序）；`_relative_node_path` 自行沿父链计算（未挂树实例的
    `get_path_to()` 返回空路径）。
11. doctest 不写真实 `project.godot`：doctest 进程跑在引擎源码树上（那里没有 `project.godot`），
    因此为 `publish_project_settings` 增加了 `publish_project_settings_to(path, …)` 入口，
    doctest 只往自己拥有的 scratch 文件发布（writer 仍是引擎的 `save_custom`）。
12. 新增/上移的计数断言（96→106 等）只随已实现并集变化，不涉语义。

待决策者批准项：

- **P-1**：是否在后续批次修 §1.5 的 **D-1**（`Variant::construct_from_string` 在本 fork 是空壳，
  使 `"Vector2(…)"` 字符串语法失效）：要么补语法（`VariantParser`/`Vector2::from_string`），要么把
  `property_value_from_json` 里那段死代码与注释删掉。当前口径是「响亮拒绝」。
- **P-2**：`project_set_setting` 对**不存在的键**是否应默认拒绝（当前允许 + 报告 `created`）。
  若决策者要求「只改已声明设置」，改动很小（一处判断），但会挡住游戏自定义设置的正规用法。
- **P-3**：`editor_execute_gdscript` 的输入上限（249 KiB）与「同帧同步执行、无超时」的取舍是否接受。
- **P-4**：`editor_set_node_script` 是否需要 UndoRedo（当前与 B3 其余编辑器写组一致地直接改 live 场景）。

---

## 8. deviations / blockers / next_step_recommendation

### deviations（与手册/任务书的偏离，逐条）

- **D-a（声明）**：本报告是**文档提交**，发生在门之后（报告必须引用门的输出）。为避免 R-1
  （陈旧二进制）假红，**五道门全部在代码冻结提交 `37f8bcb0e1` 上运行**，运行前已验证
  `--version`（`4.8.dev.custom_build.37f8bcb0e`）== `git rev-parse --short HEAD`（`37f8bcb0e1`）。
  报告提交只新增 `docs/reports/REPORT-018-b3-closure.md`，不触碰任何编译单元，因此不改变门所
  验证的那棵代码树；后续重跑门时请以 `37f8bcb0e1`（或以其为父的纯文档提交）为二进制基准。
- **D-b（声明）**：`docs/tool-groups-b3.json` 只把 6 个 `implemented` 由 `false` 改成 `true`（任务书 §3
  明文要求），**未动**任何工具名/组名/契约；`docs/tools_list.renamed.json`、`docs/tool-rename-map.json`、
  `docs/scripts/*` 一律**只读未改**（PLAYBOOK §5）。
- **D-c（声明，历史遗留）**：`check_contract_subset.ps1` 与 `accept_m1.ps1` 的「本批未实现工具不得注册」
  断言依赖 manifest 的 `implemented` 字段；B4/B5 仍全为 `false`，`--check-completeness` 退出码 0。
- **D-d（声明）**：`accept_m1.ps1` 新版 `$ToolNames` 的顺序是 manifest 顺序（旧版是手写批次顺序）。
  该顺序只出现在 `gate_scope_declared` 的 evidence 字符串里，**不参与任何断言**（`tools/list` 顺序
  不是契约，DESIGN-DETAIL §17.4）。
- **D-e（声明）**：`mcp018_b3_closure_evidence.ps1` 以 `$BaseRef`（默认 `ddb585d888`，本任务基线）
  读取「上一版脚本与 manifest」，而不是 `HEAD`——否则在提交后重跑会把新版与自身对照。
- **D-f（更正，本报告前置轮次）**：门②首轮（提交 `37f8bcb0e1` 之前）报告 `77/102`，其中 25 条失败里
  23 条是**证据脚本自身的断言错**（PowerShell `-contains` 是集合运算符；B3 在 9889 的期望应从
  rename map 的 `scope` 派生而不是从 2 个新编辑器工具派生；两条「合法值」行用了本 fork 无效的
  字符串向量语法与被改名的节点路径；`project_get_settings` 读回的 Vector2 是对象形状）。
  **真实的失败是 2 条**：`editor_execute_gdscript` 全部不可实例化（D-4，已修）与其连带的 `uid_seed`。
  这里按 append-only 勘误显式记录，不掩饰。

### blockers

无。9877（用户 Godot，PID 36392）全程未被占用/杀/重启——门①×6、门②、门⑤×2 每次都打印
`guard_user_port_9877` PASS（pid 前后相同）；测试端点只用 9888/9889；未 push。

### next_step_recommendation

1. 批准 P-1..P-4（尤其 P-1：它是本任务顺带查出、会影响后续 B4/B5 属性写族的**引擎级**事实）。
2. B4（7 个工具）可以直接沿用本批的基础设施：`ToolBuilder` + `publish_file_atomically` +
   `publish_project_settings` + `coerce_to_property_type` 的 `can_convert` 门 + `prepare_node_property_value`
   的两阶段事务；新增批次**无需**再改 `accept_m1.ps1`（§2 的目标已达成，可让 B4 作为首个验证案例）。
3. 建议把 `mcp018_b3_closure_evidence.ps1` 的四个通用能力（`$BaseRef` 对照证明、B3=40/40 的
   scope 派生、方向规则断言、坏中间文件事务反例）作为后续批次证据脚本的模板。
