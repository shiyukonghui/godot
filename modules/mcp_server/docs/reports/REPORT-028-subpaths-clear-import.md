# REPORT-028 — 收尾三小项：**G-1** 子属性路径 · **G-3** 报告读取的破坏性 `clear` · **D-1** `--import` 首次崩溃的界定与脚本加固

> 任务书：`docs/tasks/TASK-028-subpaths-clear-import.md`；手册：`docs/tasks/PLAYBOOK-group-port.md`（§3 已按本批实测**修正判据**）；
> 顺手性判据：`docs/DESIGN-DETAIL.md` §23 / GDR-25。
> 分支 `feature/mcp-server-module`，基线 `a05771bbf8`（本批无新工具、无契约变更：`tools_list.renamed.json` /
> `tool-rename-map.json` / 五份 group manifest 一字未改，`**/_meta` 指纹不变）。

## 0. status / commits

| # | sha | 一行说明 |
|---|---|---|
| 1 | `bf051fc1a6` | `TASK-028 G-1 + G-3: sub-property paths and a read that does not destroy`（实现 + doctest） |
| 2 | `ba719d483d` | `TASK-028 D-1: one hardened scratch-project --import guard for every script`（`scripts/**` + PLAYBOOK §3） |
| 3 | 本文件所在提交（`TASK-028 report: REPORT-028 …`） | `docs/reports/REPORT-028-subpaths-clear-import.md`（本条）；因为它自身就是 HEAD，**不在正文里引用自己的 sha**——见门 0 一行的说明 |

`status: **done**`（三项均已落地并有实测证据；唯一的「不做」是**读侧子路径**，理由见 §1.6，属任务书 §1.3 授权我自己判断的项）。

**为什么 G-1 与 G-3 同一条提交**：两者的 doctest 都在同一个文件 `tests/test_mcp_server.h` 里，而 `test_mcp_server.h`
的 G-3 改动（`clear` 默认语义）与 G-1 的四个新用例无法在不重写同一文件的前提下拆到两条**各自全绿**的提交里；
拆开会产生一条「测试断言了新语义、实现还是旧语义」的红提交，破坏可 bisect 性。D-1 只动 `scripts/**` 与手册，
是独立的一条。

---

## 1. G-1 —— 子属性路径（`position:y`、`v4:x`、`material:shader_parameter/<uniform>`）

### 1.1 引擎依据（为什么这是「自然形态」，不是自造的语法）

| 事实 | 位置 |
|---|---|
| `Object::set_indexed(const Vector<StringName>&, const Variant&, bool *r_valid)` / `get_indexed` | `core/object/object.h:697-698`，实现 `core/object/object.cpp:475-532` / `:534-550` |
| GDScript `node.set_indexed("position:y")` 走 `Object::_set_indexed_bind`，用 `NodePath::get_as_property_path().get_subnames()` 解析 | `object.cpp:1764-1770` |
| 路径语法：第一个 `:` 前是属性名，其后是逐段子名，**一个尾随 `:` 合法且不产生子名**；中间空段是引擎 ERR | `core/string/node_path.cpp:419-452`、`:334-349` |
| 内建类型的「有哪些成员 / 成员是什么类型」由 `Variant::has_member` / `get_member_type` / `get_member_list` 回答 | `core/variant/variant_setget.cpp:159-186`，表由 `register_named_setters_getters`（`:67-150`）填充 |
| `Variant::get_named` / `set_named`——`set_indexed` 真正的读写动词 | `core/variant/variant_setget.cpp:240-307` |
| 编辑器 Inspector 的组件写就是这条路径（本批用 `editor_set_node_property` 复现了它） | 线上证据 §1.8 |

**「一趟做完引擎一趟能做的事」**：迁移源与旧实现只有一个 `Object::get/set(名字)`，所以 `position:y` 只能
`-32001`；调用方要改一个分量就必须「读整个 Vector2 → 自己改 → 写回整个 Vector2」——这正是 GDR-25 §23.1
禁止的「调用方自己动字符串/结构」。本批把引擎本来就有的一次调用暴露出来。

### 1.2 支持范围（**按引擎**，不按模块自选的名单）

| 路径形态 | 是否支持 | 依据 |
|---|---|---|
| `position:y`（`Vector2/3/4`、`Vector2i/3i/4i` 的分量） | ✅ | `Variant::has_member` |
| `v4:x`（脚本/资源上的 `Vector4` 属性） | ✅ | 同上（线上实测 §1.8） |
| `modulate:r8`、`modulate:h`（`Color` 的 `r8/g8/b8/a8/h/s/v`） | ✅ | 同一张表；槽位 `INT32`／`FLOAT32`（GDR-24） |
| `rect:position`、`rect:size`、`rect:end`（`Rect2/Rect2i` 的**成员**） | ✅ | 引擎的成员名是 `position/size/end`，**不是** `x/y/width/height` |
| `rect:position:y`（两段以上） | ✅ | 逐段走 `Variant::get_named` |
| `material:shader_parameter/<uniform>`（嵌套 `Object`） | ✅ | `Object` 分支用模块自己的属性表判定（声明即可，未设也能写） |
| `d:key`（`Dictionary` 的**已存在**键） | ✅ | `Variant::set_named` 的 DICTIONARY 分支；槽位 `WIDE`（字典存 `Variant`，与 ProjectSettings 同理） |
| `d:new_key`（字典里不存在的新键） | ❌ `-32001` | **声明的偏离**：新键没有「声明类型」可判，「写前必过闸门」优先于「字典能加键」 |
| `arr:0`、`str:0`、`float:x`（无命名成员的类型） | ❌ `-32602` | `Variant::get_member_count(type) == 0` |
| `a::b`、`:y`（畸形） | ❌ `-32602` | 引擎语法；`:y` 是**本模块更严**（`NodePath` 会把它读成裸路径 `y`，见 §6 deviation 2） |
| `a:b:`（尾随 `:`） | ✅ 等价 `a:b` | `node_path.cpp:438-441` |
| `null_obj:x`（子路径经过一个 null 对象引用） | ❌ `-32001` | 消息明说「at 'x' is null」；不崩、不臆造成员 |

### 1.3 自然契约（新增/变化的可观察行为）

| 工具 | 变化 |
|---|---|
| `editor_set_node_property` / `running_game_set_node_property` | `property` 现可为属性路径。成功应答 **在单名时键集与形状完全不变**（`node_path`/`property`/`old_value`/`new_value`）；**路径写**额外给 `parent_property`/`parent_old_value`/`parent_new_value`（`Object::set_indexed` 真正读-改-写的那个复合值） |
| `editor_add_node.properties` / `editor_add_nodes_batch[].properties` | 键可为路径（两者都走 `write_node_property`，自动获得） |
| `editor_set_node_property_batch` | `property` 可为路径；预检由 `object_has_property(整串)` 改为 `node_property_path_exists`；回滚读**该路径**的旧值并用 `apply_node_property_value` 写回 |
| `project_set_node_property_across_scenes` | 同上（`prepare_node_property_value` 解析路径 → `apply_node_property_value` 落盘） |
| `old_value`/`new_value` 语义 | 路径写时是**该路径上的值**（`get_indexed` 的答案，即分量），复合值在 `parent_*` 里；单名写不变 |

错误码（任务书 §1.2 的判据）：

| 情形 | 码 | 消息要点（实测见 §1.8） |
|---|---|---|
| 子段不存在 | `-32001` | `Sub-property 'nope' of the property path 'position:nope' on node 'Actor' ('position' is a Vector2) not found`，`data.suggestion` = `'Vector2' has these members: x, y` |
| 首段（对象属性）不存在 | `-32001` | 沿用旧形状 `Property 'x' on node 'y' not found` |
| 类型不可 index | `-32602` | `Property path 'position:y:z' cannot be followed: 'position:y' is a float, which has no named members to index` |
| 路径畸形 | `-32602` | `Invalid property path 'position::y': the sub-property at offset 9 is empty` |
| 值过不了槽位/转换门 | `-32602` | 与整属性写**逐字同形**（`Parameter 'value' is the number 1e+300, ...`） |
| `set_indexed` 本身失败 | `-32000` | `The engine refused to write the value … through the property path …`（罕见；写前已校验） |

### 1.4 落点

| 位置 | 内容 |
|---|---|
| `tools/running_game_node_write.cpp`（新增 §"TASK-028 G-1" 段，`:608-908`） | `split_property_path`（语法）/ `_path_member_slot`（槽位）/ `_path_member_of`（成员查询）/ `_member_list_hint` / `_resolve_property_path`（逐段解析 + 两种拒绝）/ `read_node_property_path` / `apply_node_property_value` / `node_property_path_exists` |
| 同文件 `write_node_property` / `prepare_node_property_value` | 单名分支**逐字保持**；`>1` 段走 `_prepare_sub_property_value` + `get_indexed`/`set_indexed` |
| `tools/running_game_node_write.h` | 四个导出入口的声明与设计说明（供 batch / cross-scene 用，避免它们各写一份） |
| `tools/editor_node_batch_write.cpp` | 预检 + 回滚路径化 |
| `tools/project_cross_scene_write.cpp` | `->set(StringName(p_property), …)` → `apply_node_property_value` |

**「不得新开绕过分支」怎么落实**：路径写的值走的是**同一条三段链**
`property_value_from_json` → `shape_vector_from_json` → `coerce_to_property_type`（其中 `value_fits_slot` 是
GDR-22/GDR-24 唯一的宽度判定），**唯一区别**是「申明类型/槽位」的来源从 `property_type_of(整属性)` 换成
`_resolve_property_path(最后一段)`。写动作本身是引擎的 `Object::set_indexed`，没有第二个写路径。新增的槽位映射
只回答「这一段的成员存在哪种宽度的 C++ 成员里」：

* `Color` 的 `FLOAT` 成员 → `FLOAT32`（GDR-24，跨构建恒定）；其它 `FLOAT` 成员 → `REAL_T`；
* `Vector2i/3i/4i`、`Rect2i`、`Color` 的 `INT` 成员 → `INT32`；其余 `INT` → `scalar_member_slot` 的 `WIDE`（诚实边界，与标量属性同一规则）；
* `Dictionary` 成员 → `WIDE`（真存 `Variant`）。

**未新增任何收窄点**：门⑥ 仍 30/30（全部为既有 pin，行号已随本次插入同步）。

### 1.5 与迁移源的差异及理由

| 差异 | 迁移源 | 本实现 | 理由 |
|---|---|---|---|
| 什么都不支持子路径 | `node.rs:221`（`update_property`）只 `set(name)` | 支持引擎语法 | **引擎是第一参考源**（D74/GDR-23）：引擎一次调用能做到，就不该让调用方做多步舞蹈 |
| 未知属性 | 静默成功形状 | `-32001` + 建议（TASK-014 D-1 已定） | 沿用 |
| 路径不存在的措辞 | 无此情形 | 消息**指名**哪一段 + 引擎自己的成员清单 | 任务书 §1.2「消息要可读且指名哪一段不存在」 |
| 字典新键 | 无此情形 | `-32001`（拒绝） | 写前必过闸门；无声明类型可判（**偏离**，已登记） |

### 1.6 读侧结论：**不加**子路径（任务书 §1.3 授权自判）

**结论：读侧（`editor_get_node_properties` / `running_game_get_node_properties`）继续只接受属性名，不接受子路径。**

理由（三条，按强度排序）：

1. **没有顺手性缺口**。写侧必须支持子路径，是因为 `set` 无法表达「一个分量」——调用方只能「读整个值 → 自己改 → 写回」，
   而「自己改」就是 GDR-25 §23.1 禁止的字符串/结构手术。读侧相反：**一次调用读整个 `position` 就拿到了全部分量**，
   调用方从 `{"x":1.0,"y":3.0}` 里取 `y` 是 JSON 取值，**不是手术**，而且信息比只读一个分量**更多**、
   调用次数**相同**。任务书的判据是「引擎一趟能做的事、返回可链式喂回」，读侧已经满足。
2. **加了要动契约**。`properties` 是一个 filter 列表，若它开始接受路径，就必须在 `description` 里写明第二套词法
   （或加参数）；而 `docs/tools_list.renamed.json` 是逐字门对象，改它要走 `DESCRIPTION_OVERRIDES` + 重生成 + 全部指纹
   （GDR-25 §23.2 第 5 条）。任务书明确说「改描述要报给决策者」，为一个**没有缺口**的便利去动契约不划算。
3. **对称性由写侧给出**：写侧同时接受 `position`（整值）与 `position:y`（子路径）；读侧答 `position` 后，
   写侧两种形态都能把读到的值喂回去（§23.4 闭合规则满足）。

已用 doctest 把这个决定**钉住**（`TASK-028 G-1: the read side answers whole properties only, and says so`）：
`properties: ["position:y"]` 仍是 `-32001`（且消息里带路径名），`properties: ["position"]` 答出两个分量。

### 1.7 红/绿（真实输出）

**红**（把 G-1 的分派 `if (segments.size() > 1)` 临时改成 `if (false && …)`，其余不动；`build_local.cmd -Force` 后运行）：

```
[MCPServer] TASK-028 G-1 … 3 failed of 4
  test_mcp_server.h(15475): FATAL ERROR: REQUIRE( written.get_type() == Variant::DICTIONARY ) is NOT correct!
    logged: Property 'd:k' on node 'Object' not found
  test_mcp_server.h(15465): ERROR: CHECK( (int)material->get_blend_mode() == 2 ) is NOT correct!  values: CHECK( 0 == 2 )
[doctest] test cases: 4 | 1 passed | 3 failed | 1642 skipped
[doctest] assertions: 86 | 50 passed | 36 failed
[doctest] Status: FAILURE!
```

**绿**（恢复分派后）：

```
[doctest] test cases: 4 | 4 passed | 0 failed | 1642 skipped
[doctest] assertions: 92 | 92 passed | 0 failed
[doctest] Status: SUCCESS!
```

### 1.8 线上证据（`--data-binary @file` + sha256；完整日志 `%TEMP%\task028-subpaths-clear\evidence\`）

**脚本**：`scripts/mcp028_subpaths_clear_import_evidence.ps1`，**27/27 PASS，exit 0**。

| 检查 | 请求 → 响应（截断） | sha256（响应体） |
|---|---|---|
| `G1_position_before` | `editor_get_node_properties{Actor,["position"]}` → `{"position":{"x":1.0,"y":2.0}}` | `0874c22b…3b193c50` |
| `G1_set_position_y` | `editor_set_node_property{Actor,"position:y",3}` → `{"new_value":3.0,"old_value":2.0,"parent_property":"position","parent_new_value":{"x":1.0,"y":3.0},"parent_old_value":{"x":1.0,"y":2.0},"property":"position:y","node_path":"Actor"}` | `4edab94f…47efc936` |
| `G1_position_after`（**另一个工具**读回） | `editor_get_node_properties{Actor,["position"]}` → `{"position":{"x":1.0,"y":3.0}}` | `19ed8949…3eb7c21e` |
| `G1_position_again`（§23.4 第 ③ 层：再读一次） | 与上**同 sha256** `19ed8949…` | 同上 |
| `G1_v4_x` | `editor_set_node_property{Actor,"v4:x",9}` → `{"new_value":9.0,"old_value":1.0,"parent_new_value":{"w":4.0,"x":9.0,"y":2.0,"z":3.0},…}`；`G1_v4_after` 再读回 `v4={"w":4.0,"x":9.0,"y":2.0,"z":3.0}` | `04957cda…6d6fe250f` / `eb9254c0…6536510ae` |
| `G1_set_shader_param`（**嵌套 Object**） | `editor_set_node_property{Actor/Sprite2D,"material:shader_parameter/uv1_scale",2.5}` → `{"new_value":2.5,"old_value":null,"parent_property":"material","parent_new_value":{"path":"res://probe_material.tres","type":"ShaderMaterial"},"property":"material:shader_parameter/uv1_scale"}` | `0614c91f…455e9ac3` || `G1_gate_position_y_1e300`（**同一道闸门**） | → `-32602` `Parameter 'value' is the number 1e+300, which does not fit in the 32-bit float slot …`；随后读回 `position` 仍是 `{"x":1.0,"y":3.0}`（旧值存活） | `bffb45fe…7b7ef9` |
| `G1_missing_segment`（负例 1） | `position:nope` → `-32001` `Sub-property 'nope' of the property path 'position:nope' on node 'Actor' ('position' is a Vector2) not found`，`suggestion='Vector2' has these members: x, y` | `7c818136…11a6f596` |
| `G1_not_indexable`（负例 2） | `position:y:z` → `-32602` `Property path 'position:y:z' cannot be followed: 'position:y' is a float, which has no named members to index` | `f6d6a83d…7fd6243b` |
| `G1_malformed_path` | `position::y` → `-32602` `Invalid property path 'position::y': the sub-property at offset 9 is empty` | `7a4c10cc…308e16ba` |
| `G1_batch_set_position_y`（批量语义一致） | `editor_set_node_property_batch{Node2D,"position:y",7}` → `{"count":3,"node_type":"Node2D","nodes":[".","Actor","Actor/Sprite2D"],"property":"position:y","status":"ok","updated":3}`，读回 `{"x":1.0,"y":7.0}` | `2398455b…ad5cb951` |
| `G1_batch_not_indexable` | → `-32602`（与 `G1_not_indexable` **响应体同 sha256**：同一条消息、同一个 id） | `f6d6a83d…7fd6243b` |

> 表中 `old_value: null`（`material:shader_parameter/uv1_scale` 首次写入）是**引擎语义**而非缺陷：
> `ShaderMaterial::_get`（`scene/resources/material.cpp:235-246`）对「从未写过的 uniform」只回 `remap_cache`
> 里已有的项，所以首次写之前读它是空的；写成功后 `new_value` 就是读回的 `2.5`。
> 一个「从未设过的 uniform」在引擎里是**声明存在**（在 `_get_property_list` 里，本模块据此判定它存在并可写）、
> **值未读**，两者不矛盾。


**跨工具链（零字符串手术）**：`editor_get_node_properties(Actor)` → 取 `position` 对象 → 只改 `y`
→ `editor_set_node_property(Actor,"position:y",3)`；整条链里调用方**没有**解析/拼接任何字符串，
参数全部来自上一条响应（`editor_add_node` 的 `node_path` 同理可直喂）。

---

## 2. G-3 —— `editor_get_test_report` 的 `clear` 语义裁决

### 2.1 裁决与理由

**裁决：`clear` 由「默认 true」改为「显式 opt-in」——缺省与 `false` 都是纯读取，只有显式 `clear: true`
才清空。**（任务书 §2.1 给的第二个选项「把清与读分成两条清晰语义」，本实现就是它的最小形态：
「不带参数 = 读」「带 `clear: true` = 读并清」。）

理由：

1. **桥接文件是共享的**（`user://mcp_test_report.json`，同一工程的每个客户端共用），旧默认值让「先读的人」
   删掉「后读的人」还没读的报告——**读取带破坏性副作用**，这是 M4c 的 G-3。
2. **默认值必须选安全的一侧**。`clear` 是「清」的开关，不是「读」的开关；把它默认成 `true` 等于让
   「查一下报告」这个动作默认具破坏性。按最小惊讶原则，缺省必须是**非破坏**。
3. **响应仍然诚实**：`cleared` 明确列出这次真正清掉了哪一半（`editor_process` / `game_process_file`），
   纯读取时是 `[]`；游戏进程的**内存**本进程够不到，也没有被声称清掉（沿用 TASK-022 的措辞）。
4. **空的/不可达时维持诚实空**：`total: 0` + `no_results: true` + `pass_rate: "N/A"` +
   `report_unavailable_reason`（实测见 §2.4），**不伪造 total**。

### 2.2 与已注册 `inputSchema` 的**不一致**（→ 报给决策者，≠ 自行走 override）

已注册的 `inputSchema` 仍是契约逐字：

```json
"clear": {"default": true, "description": "是否清除结果", "type": "boolean"}
```

契约文件 `docs/tools_list.renamed.json` 是逐字门的对象，且任务书明确「若涉及 inputSchema 的 default，
**报给决策者，不要自行走 override**」，所以本批**没有**改注册 schema（门① 因而不是问题），
但这意味着：**声明的 `default: true` 与实现的「缺省不清」目前不一致**，这是一个**待决策的契约缺陷**。

**给决策者的建议**（两条，任选，都需要走 `SCHEMA_OVERRIDES(mode=replace)` + 重生成 + 全部指纹）：

* 方案 A（推荐，最小）：`clear.default` 由 `true` 改 `false`，并在 `description` 里写明「缺省为纯读取；
  显式 `clear: true` 会删除**共享**桥接文件，影响同一工程的所有客户端」。逐字引用被替换的成员：
  `{"default": true, "description": "是否清除结果", "type": "boolean"}`。
* 方案 B：保留 `default: true`，把 `clear` 限定为「只清本进程累积器」，另设一个显式参数
  （如 `clear_shared_report`）承担共享文件的删除——**新增参数，属 schema 结构变更**，代价更大。

在决策者落笔之前，**实现按安全侧运行**（缺省不清），本报告与 §2.4 的证据即为该行为的可核验记录。

### 2.3 多客户端安全（实测）

同一编辑器进程、**两个客户端先后读取**（请求体里**没有** `clear` 字段）：

| 客户端 | 应答要点 | 响应体 sha256 |
|---|---|---|
| A（第 1 个） | `total=2, passed=1, failed=1, source=game_process_file, cleared=[]`，桥接文件仍在 | `0e4a71d8…979da88f`（914 B） |
| B（第 2 个） | **与 A 的 sha256 完全相同**（914 B） | `0e4a71d8…979da88f` |

→ **先读方仍能读到完整报告**，且后读方读到的字节与先读方一致（文件没被改、没被删）。

随后显式 `clear: true`：`cleared=["editor_process","game_process_file"]`（sha256 `aaa1de2a…64d7b3a`），
文件消失，**再读**得 `total=0 / no_results=true / report_file_present=false / report_unavailable_reason="'user://mcp_test_report.json' does not exist"`（sha256 `44222582…98a11b5`）。

### 2.4 红/绿（真实输出）

**红**（把 `clear` 默认恢复成 `true`、分派保持不动，`build_local.cmd -Force` 后运行）：

```
[MCPServer] TASK-022 D-6 … 1 failed of 2
  test_mcp_server.h(13361): ERROR: CHECK( (int)report.get("total", 0) == 1 ) is NOT correct!  values: CHECK( 0 == 1 )
  test_mcp_server.h(13362): ERROR: CHECK( (bool)report.get("no_results", true) == false ) is NOT correct!  values: CHECK( true == false )
  test_mcp_server.h(13367): ERROR: CHECK( FileAccess::exists(bridge_file()) ) is NOT correct!  values: CHECK( false )
[doctest] test cases: 2 | 1 passed | 1 failed | 1644 skipped
[doctest] assertions: 65 | 58 passed | 7 failed
[doctest] Status: FAILURE!
```

即：**第二个读者的 total 掉到 0、文件被删**——正是 G-3 描述的破坏。
**绿**（恢复后）：`2 | 2 passed | 0 failed`，`65 | 65 passed`。

---

## 3. D-1 —— 全新工程首次 `--import` 的 `0xC0000005`

### 3.1 最小复现与反向对照：**复现不出来**

**脚本**：`scripts/mcp028_import_crash_probe.ps1`（7 个变体 × 6 次 ×「首导 + 同目录二导」= **84 次全新工程首导**，
每个变体都在**全新目录**里、没有 `.godot`）。

| # | 变体 | 首导 exit | 二导 exit | `.godot` 生成 | stderr 有 `is_cmdline_mode` | stderr 有 `Parse Error` |
|---|---|---|---|---|---|---|
| 1 | `.tscn`，无 BOM，`--mcp-port=0`（**TASK-027 的形态**） | 0 ×6 | 0 ×6 | 是 | 否 | 否 |
| 2 | `.tscn` **带 BOM**，`--mcp-port=0`（**M3 记载的形态**） | 0 ×6 | 0 ×6 | 是 | 否 | 否 |
| 3 | `.tscn` + `project.godot` **都带 BOM** | 0 ×6 | 0 ×6 | 是 | 否 | 否 |
| 4 | **不含 `.tscn`**（TASK-026 的对照） | 0 ×6 | 0 ×6 | 是 | 否 | 否 |
| 5 | `.tscn`，**完全不给 `--mcp-port`**（编辑器取默认 9877——**已被用户 Godot PID 36392 占用**） | 0 ×6 | 0 ×6 | 是 | 否 | 否 |
| 6 | `.tscn`，`--mcp-port=9888`（模块真的 listen） | 0 ×6 | 0 ×6 | 是 | 否 | 否 |
| 7 | `.tscn` 含 `ext_resource`（引用 `res://probe.gd`）+ 无 BOM | 0 ×6 | 0 ×6 | 是 | 否 | 否 |

**汇总**：`runs total: 84`，`runs non-zero exit: 0`，`parse_error runs: 0`；9877 的 PID 前后都是 `36392`（未触碰）。
另有两次补充实验（都在本轮，全部 exit 0）：

* **重建后立刻**（`build_local.cmd -Force` 会强制 relink，正是历史崩溃的时点）再跑 **32 次**全新首导：全 0；
* 更早的手工变体（`[rendering]` + `.tres` + `.gd` 的 TASK-027 复刻、8×2 组）**16 次**首导：全 0。

**结论（逐项排除）**：

| 候选触发条件 | 判定 |
|---|---|
| `.tscn` 是否存在 | **排除**：含与不含都 0；TASK-027 的反向对照（「不含 `.tscn` 首次即 0」）现在两边都是 0 |
| `.tscn` / `project.godot` 的 **BOM** | **排除**：BOM 变体 12 次首导全 0，且**一次 `Parse Error` 都没有**（本 fork 的 4.8 场景解析器接受 BOM） |
| `.godot` 缺失 | **排除**：每次首导都无 `.godot`，`.godot=True`（导入真的完成了）；二导（`.godot` 已在）同样 0，不构成差异 |
| `--mcp-port` 是否给 / 给什么 | **排除**：缺省（会去 bind 被占用的 9877）/ `=0`（listen=false）/ `=9888`（listen=true）三种都是 0——模块的 bind 失败路径不崩 |
| `.tscn` 内容（`ext_resource` 引用 / 文件大小） | **排除**：第 7 变体 6 次全 0 |
| 「刚 relink 完的第一个进程」 | **排除**：relink 后立刻 32 次全 0 |

### 3.2 根因判定：**无法归因到本模块；判为引擎侧间歇性缺陷（当前不可复现）**

* **无法归因到模块**：崩溃发生点若真在模块里，`--import` 的形态（无端口 / 有端口 / 不同工程内容）
  应产生差异；实测三种端口形态、七种工程形态**都没有差异**。模块的 `MCPServer::bootstrap` 在
  `--import` 下即使被调到，也只做「给 SceneTree root 加一个 Node」这件引擎日常操作，且 §3.1 显示
  无端口时 `listen=false`（不碰 socket）也全 0。
* **唯一可复现的引擎侧痕迹**（我在实验早期的一次首导 stderr 里**亲眼见到**，mcp016 的注释也记录了同一行）：

  ```
  ERROR: Parameter "singleton" is null.
     at: EditorNode::is_cmdline_mode (editor\editor_node.cpp:6732)
  ```

  来源是引擎代码 `editor/file_system/editor_file_system.cpp:2301` → `EditorNode::is_cmdline_mode()`
  （`editor_node.cpp:6731-6734` 里是 `ERR_FAIL_NULL_V(singleton, false)`，所以该行本身**不崩**、只是报错）。
  这条痕迹**不指向模块**（`modules/mcp_server/**` 里没有任何调用者），而且**它自身也是间歇的**
  （84 次受控实验里 0 次出现；手工实验里 4 个日志里出现 1 次）。所以它只是「引擎在 `--import` 收尾阶段
  会走到 singleton 已销毁的路径」的旁证，不是崩溃点的证明。
* **历史记载**：`0xC0000005`（exit `-1073741819`）在本项目里被记录过 **4 次**（M3 报告、`mcp016` 的注释、
  `mcp026` 的脚本注释、`REPORT-027` §D-1），其中 `mcp016` 明确写「**intermittent** engine crash, not a
  property of the project」。结合本批 132 次受控首导全 0，**该崩溃是低频、非确定、与工程内容无关的
  进程级访问违例**。

### 3.3 撤回声明（PLAYBOOK §7.3：无法复现的主张必须显式撤回）

| 旧主张 | 出处 | 处置 |
|---|---|---|
| 「`.tscn` 带 UTF-8 BOM 的工程首次 `--import` **会**以 `0xC0000005` 退出，stderr 有 `Parse Error: Expected '['`」 | `PLAYBOOK §3`（M3 验收的旧文） | **撤回**：BOM 变体 12 次首导全 0，`Parse Error` 0 次。已在 PLAYBOOK §3 就地改写 |
| 「**全新工程 + 含 `.tscn`** 时首次 `--import` **必崩**」 | `REPORT-027` §D-1、`REPORT-027` §7.1 | **降级为「低频、非确定、不可复现」**：84 + 32 + 16 = 132 次受控首导全 0。`mcp026` / `mcp027` 的脚本注释同步改写（`mcp027` 的检查 id 保留，证据文本改为记录 attempts） |
| 「与本次改动无关，登记供决策者决定」 | `REPORT-027` §7.1 | 采纳：本批给出了 §3.2 的归因判定与 §3.4 的上游材料；**不**动引擎代码 |

### 3.4 上游可提交的最小复现材料

因为崩溃不可复现，材料是「命令 + 文件 + 当时观察到的退出码与 stderr」，可直接贴给上游 issue：

```
# 命令（Windows, 4.8.dev.custom_build）
bin\godot.windows.editor.x86_64.console.exe --headless --mcp-port=0 --path <NEW-EMPTY-PROJECT> --import
# 观察到的退出码（历史上 4 次）
-1073741819   (= 0xC0000005, access violation)
# 第二次运行同一目录
0
# 同一个目录，如果不含 .tscn
0（第一次就是 0）

# 最小工程内容（无 BOM；本批实测此内容复现不出来，但就是历史事故用的那一份）
project.godot:
    config_version=5

    [application]
    config/name="probe"
    run/main_scene="res://scenes/main.tscn"
    config/features=PackedStringArray("4.8")

scenes/main.tscn:
    [gd_scene format=3]

    [node name="Main" type="Node2D"]

# stderr 上唯一可见的引擎侧痕迹
ERROR: Parameter "singleton" is null.
   at: EditorNode::is_cmdline_mode (editor\editor_node.cpp:6732)
# （调用点：editor/file_system/editor_file_system.cpp:2301，
#   EditorFileSystem::_process_update_pending → EditorNode::is_cmdline_mode）
```

**提交脚本**：`scripts/mcp028_import_crash_probe.ps1 -Repetitions 6`（可直接跑，输出 `summary.json` + 每个变体
的 `*.log`）。**建议上游动作**：把 `EditorNode::is_cmdline_mode()` 的调用点改为可空安全 / 或用
`EditorNode::get_singleton()` 判空，然后由上游在带符号/调试版上复跑上述矩阵——本 fork 未做此改动
（任务书 §3 明确「界定 + 加固，不是修引擎」）。

### 3.5 脚本加固（`scripts/**`）

**唯一的实现**：`scripts/mcp_import_guard.ps1`（新增）

* `Write-McpUtf8NoBom`（`[IO.File]::WriteAllBytes` + `UTF8Encoding($false)`）
* `New-McpScratchProject`（整套 scratch 工程，每个文件都无 BOM）
* `Import-McpProject`（**校验退出码** + **有界重试**（默认 3 次）+ **每次失败打印诊断**（命令行、退出码十进制与
  `0x…`、工程路径、日志路径、日志尾部）+ 失败重试耗尽后抛出带诊断的异常；引擎二进制不存在时给出**可诊断**的
  throw，而不是 PowerShell 的 `CommandNotFoundException`）

**加固前后对照**（逐调用点）：

| 脚本 | 加固前 | 加固后 |
|---|---|---|
| `accept_m1.ps1`（门⑤） | `Set-Content -Encoding UTF8`（**写 BOM**）；`Import-Project` 起进程、`WaitForExit`、**不看退出码** | `Write-McpUtf8NoBom` + `Import-McpProject`（校验 + 重试 + 诊断） |
| `check_contract_subset.ps1`（门①） | 同上（BOM + 不校验） | 同上 |
| `mcp014_m3_evidence.ps1` | 4 处 `Set-Content -Encoding UTF8`（BOM）；`Import-Project` 不校验 | 全部改 `Write-McpUtf8NoBom`；`Import-McpProject` |
| `mcp009`–`mcp013` | `Start-Process … --import` + `WaitForExit`，**退出码丢掉** | 统一 `Import-McpProject` |
| `mcp015` | 校验退出码但**只跑一次**（无重试） | 统一 `Import-McpProject`（3 次） |
| `mcp016`–`mcp023` | 各自一份 3 次重试循环；`mcp020`–`mcp023` 失败时**不打印 stderr** | 统一 `Import-McpProject`（自带诊断） |
| `mcp024b` / `mcp025` / `mcp026_e9_e6` | 各自一份 3 次循环，throw 消息无诊断 | 统一 `Import-McpProject` |
| `mcp024a` | 校验 `exit == 0` 但**无重试**（一次瞬时崩溃即整套证据红） | `Import-McpProject` |
| `mcp026_object_shape_probe` | 同上 | `Import-McpProject` |
| `mcp027` | 跑两次、只断言第二次为 0（把崩溃当成常态） | 两次都走 `Import-McpProject`；检查 id 保留，evidence 记录 attempts |

**加固后的真实运行片段**（门① 的一次完整运行，`%TEMP%\mcp028\gate1-final.log`）：

```
importing scratch projects ...
import[subset-import-editor] attempt 1/3 exit=0 project=…\godot-mcp-subset-scratch\editor log=…\subset-import-editor.attempt1.log
import …\editor: exit 0 on attempt 1
import[subset-import-game] attempt 1/3 exit=0 project=…\godot-mcp-subset-scratch\game log=…\subset-import-game.attempt1.log
import …\game: exit 0 on attempt 1
```

**失败路径的真实演示**（用一个「永远崩」的 stub 引擎，证明规则 ②③④ 是代码不是文字）：

```
import[stub] attempt 1/2 exit=-1073741819 project=…\proj log=…\stub.attempt1.log
  DIAGNOSTIC: …\stub-engine.cmd --headless --mcp-port=0 --path …\proj --import
  DIAGNOSTIC: exit code -1073741819 (0xC0000005), project …\proj
  DIAGNOSTIC: log …\stub.attempt1.log, tail:
    import| stub-engine.cmd : stub: simulating a crashed --import
    …
import[stub] attempt 2/2 exit=-1073741819 …
THROWN: --import of "…\proj" failed 2 time(s); last exit code -1073741819 (0xC0000005); see …\stub.attempt2.log
```

以及 no-BOM 的机器校验（同一演示的一部分）：

```
project.godot bytes=248 first3=99,111,110 has_bom=False
main.tscn     bytes=52  first3=91,103,100 has_bom=False
```

> 注：三个历史证据脚本（`mcp022`/`mcp023` 的 D6 段）还按 G-3 的新语义改写了「默认清空」那一步
> （改成「两次纯读非破坏」+「显式 `clear: true` 才清」）。它们是**证据生成器**而非历史记录（历史记录是报告），
> 留着会得到一条已知必然失败的检查；改动已登记在 §6 deviations。

### 3.6 PLAYBOOK §3 的更新（允许直接改手册，未新增规范章节）

`docs/tasks/PLAYBOOK-group-port.md` §3 里 M3 的那段「⚠️ scratch 工程的 `.tscn` 不要写 BOM，且门脚本必须校验
`--import` 的退出码」已**就地改写**为四条纪律：①一律无 BOM（并点名三个曾经写 BOM 的脚本）；
②退出码必须校验（半导入的工程会污染此后所有断言）；③必须有界重试 + 每次失败打印可诊断信息（点名共享助手
与已改造的脚本范围）；④**修正判据**：写明「带 BOM 必崩」「含 `.tscn` 首次必崩」都不成立、旧记载是间歇性
引擎侧崩溃、本批 84 次实测无法复现，纪律不依赖「哪个变体触发」而依赖「校验 + 重试 + 诊断」。

---

## 4. 门（全部自己跑，贴真实输出与退出码）

| 门 | 命令 | 结果 |
|---|---|---|
| 0 绑定构建 | `scripts\build_local.cmd -Force`（`tests=yes`） | exit 0；`--version` 与 `git rev-parse --short HEAD` **相同**（本批每次改动后都重建复验，**包括本报告提交之后**；G-1/G-3 的实现提交是 `bf051fc1a6`，D-1 是 `ba719d483d`，无需引用报告提交自身的 sha——提交一下载 HEAD 就会变，引用它必然失真） |
| ① 契约子集逐字 | `scripts\check_contract_subset.ps1` | **exit 0**，`3/3 checks passed`：`PASS editor_9888_contract_subset`、`PASS game_9889_contract_subset`、`PASS guard_user_port_9877`；`implemented_union=91(editor)/53(game)`；逐字 name/description/inputSchema 全 True |
| ② 三类证据 + 活证据链 | `scripts\mcp028_subpaths_clear_import_evidence.ps1` | **exit 0，27/27 PASS**（成功 12 条、缺参/畸形 3 条、底层失败/类型不可 index 3 条、闸门拒绝 1 条、批量一致 2 条、G-3 6 条）；响应体全部落盘 + sha256（§1.8/§2.3） |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | `test cases: 217 \| 217 passed \| 0 failed`，`assertions: 8415 \| 8415 passed \| 0 failed`，`Status: SUCCESS!`（**在最终 HEAD 构建的二进制上复跑**） |
| ④ 全引擎回归 | `--headless --test` | `test cases: 1643 \| 1643 passed \| 0 failed \| 3 skipped`，`assertions: 432697 \| 432697 passed \| 0 failed`，`Status: SUCCESS!`（**在最终 HEAD 构建的二进制上复跑**） |
| ⑤ 批收口 | `scripts\accept_m1.ps1` **连跑两次** | 两次都 **exit 0，22/22 cases passed**，两次 PASS 清单 **IDENTICAL**（`Compare-Object` 无差异）；`implemented tools = 91(editor)/53(game)`，`contract = 171`；`guard_user_port_9877` 两次都 PASS |
| ⑥ 收窄点清单 | `python scripts\check_narrowing_points.py` | **exit 0**：`scanned 30 / pinned 30`，无 drifted 条目（本次把 TASK-028 插入导致漂移的 8 个行号同步进 `PINNED`），`PASS: every narrowing point …` |
| — 回归：TASK-027 证据脚本重跑 | `scripts\mcp027_object_shape_and_paths_evidence.ps1 -Phase green` | **exit 0，61/61 checks passed**，`E2_zero_string_surgery_chain` PASS，`port_9877_owner_after` PASS → **TASK-028 未回退 TASK-027** |
| — D-1 探针 | `scripts\mcp028_import_crash_probe.ps1 -Repetitions 6` | exit 0：`runs total 84 / non-zero 0`，9877 前后同 PID |

**端口纪律**：全程未占用/未杀/未重启 9877（用户 Godot 4.7.1-mono，PID `36392`，门①/⑤/探针/证据脚本每次都记录
前后 PID 相同）；测试用 9888/9889；scratch 全在 `%TEMP%`。**未 push**。

---

## 5. 本批改动文件与 sha256

| 文件 | sha256（工作树） |
|---|---|
| `tools/running_game_node_write.cpp` | `c76744c1899ce12699e44e74dd1e31faaa389128ac21fc7e27a604548e7b8b91` |
| `tools/running_game_node_write.h` | `9bdd2f9e8a51681ef99acaad3f394bdf5bcd4ca8742f9cb1d9691cc2869d49f6` |
| `tools/editor_node_batch_write.cpp` | `03b8e39fb3c91f1e071127eb04a6c0295c95ea14c17a8966f513af4362496d28` |
| `tools/project_cross_scene_write.cpp` | `9961364f5c30bde9e9a112861d9c420872671b750f054ea4ae61ef5523c7ab98` |
| `tools/editor_testing_read.cpp` | `53184519fee1cbdf7a0f009cb212369a430dbab3a86d9ce9aaeac2f3bde6c595` |
| `tests/test_mcp_server.h` | `a956d9502fdd960ec0038ead6ddd6ba7f1b1a4cbd60dff5af4bd396464e39898` |
| `scripts/mcp_import_guard.ps1`（新） | `dd859fd40fa09a6ce10cf8edb613e843852c0bd50a684d9a597304a0fe5749ef` |
| `scripts/mcp028_import_crash_probe.ps1`（新） | `2795f591d56fafc76041e104912e55795132e562b6885d0c049196541a90dc7d` |
| `scripts/mcp028_subpaths_clear_import_evidence.ps1`（新） | `c66d6f19ad0553ce6d027b343543b6984067105f31e7b75eb9218f9ced1ba107` |
| `scripts/check_narrowing_points.py` | `a1cfb1c41166eba1da6ac5b4ab996a8e08ce678a964dc5d8d8c2814d8c2d16b1` |
| `scripts/accept_m1.ps1` | `d992c634fd200124876851cd93488cbc3556bbc63dde3c48767b96a775c56140` |
| `scripts/check_contract_subset.ps1` | `c1d169f8c0a68d3a689913c767fe1d3461b609060299b7cecc76b2d93ed72b48` |
| `docs/tasks/PLAYBOOK-group-port.md` | `ecbd48653160009d5d792ef1cd71f44f34ffd178d481d5c0036a05206c60cf2f` |

**契约/映射/生成器**：`docs/tools_list.renamed.json`、`docs/tool-rename-map.json`、`docs/tool-groups*.json`、
`scripts/gen_*.py` **一字未改**（门① 逐字通过即为证明；`_meta.map_sha256` 等指纹未变）。

---

## 6. deviations（逐条显式列出）

1. **G-1 的应答新增三个键**（`parent_property`/`parent_old_value`/`parent_new_value`，**仅路径写**）。
   理由：`Object::set_indexed` 是「读复合值 → 改成员 → 写回复合值」，只给分量会让调用方看不到复合值的其余部分；
   这三个键让「这个写到底把 `position` 变成了什么」一次可见。**单名写不产生它们**（键集与形状与旧实现逐字一致）。
2. **严格化 `:y`**：`NodePath` 会把前导 `:` 的路径读成裸路径（`":y"` → `["y"]`）；本模块按畸形路径 `-32602`。
   理由：`:y` 不是任何调用方会写的「属性路径」，静默重解释比拒绝更危险。
3. **字典新键拒绝**（`d:new_key` → `-32001`）：引擎允许加键，但没有声明类型可过闸门。取「写前必过闸门」优先。
4. **读侧不加子路径**：见 §1.6（任务书 §1.3 授权自判）。
5. **G-3 的运行时默认与已注册 schema 的 `default: true` 不一致**：见 §2.2，**已报给决策者**，未自行走 override。
6. **改写了 `mcp022` / `mcp023` 的 D6 证据段**：它们断言的是 TASK-022 时期的「默认清空」，在新语义下必然失败。
   已改为「两次纯读非破坏 + 显式 clear 才清」，检查 id 保留、新增 `D6_plain_read_is_non_destructive`。
7. **改写了 `PLAYBOOK §3` 的 M3 判据**（撤回 BOM 归因），并同步 `mcp026`/`mcp027` 的脚本注释；
   `mcp027` 的检查 id `scratch_project_import_second_run` 保留，evidence 文本改为记录 attempts。
8. **`check_narrowing_points.py` 的 8 个 pin 行号同步**（TASK-028 插入导致 +1 / +27）。门⑥ 本来自带
   「identity index，行号漂移不算失败」的说明，但把清单保持精确更省下一次误判。
9. **未触碰引擎代码**：D-1 只做界定 + 脚本加固（任务书 §3 明确）；上游建议写在 §3.4。
10. **`.tscn` 一律不写 BOM** 仍是纪律（即使本批证明 BOM 不是崩溃原因）：Godot 的文本格式对 BOM 的处理属于
    引擎内部细节，不写 BOM 是零成本的确定行为。

## 7. blockers

**无**。（`0xC0000005` 本身「不可复现」是 D-1 的**结论**而非阻塞：任务书允许「不能归因就明说引擎侧缺陷并给上游材料」。）

两件留给决策者的事（都需要契约变更，故不在本批自行处理）：

1. `editor_get_test_report` 的 `clear.default`：建议方案 A（改 `false` + 改描述），文本见 §2.2。
2. 是否把 §3.4 的上游材料提给 Godot 上游（本 fork 是否修 `EditorNode::is_cmdline_mode` 的可空调用属另一批的决策）。

## 8. next_step_recommendation

1. 决策者就 §2.2 的两个方案之一落笔；落笔后需要一次「override + 重生成 + 全指纹」的小批（`SCHEMA_OVERRIDES`
   `mode=replace` + `DESCRIPTION_OVERRIDES`），并重跑门①。
2. 若决定把 §3.4 提上游：附 `scripts/mcp028_import_crash_probe.ps1` 与 84 次全 0 的 `summary.json`
   （`--mcp-port` 三形态 + BOM 两形态 + `ext_resource` 一形态），并说明「只能提供历史观察，无法提供本地复现」。
3. 剩余 58 个未实现工具（113/171）按既有批次继续；GDR-25 顺手性清单里已登记但未做的项（如
   `Transform2D/Transform3D/Basis` 等结构体类型的读回形状）建议在实现到它们的工具时按 §23.4 一并给出。