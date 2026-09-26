# REPORT-020 — TASK-020: 修复 M4 验收的 3 个缺陷（静默错值残留 + 断言字段）并补两项未验证项

- 任务书：`docs/tasks/TASK-020-m4-defect-fixes.md`（规范：`docs/tasks/PLAYBOOK-group-port.md`）
- 执行者：实现工程师（**未参与** M4 验收；本报告全部结论均由本次自行运行产生）
- 日期：2026-09-22
- 仓库：`F:\RustProjects\godot-mcp-pro\code\godot`（分支 `feature/mcp-server-module`）
- `status`：**完成**（D-1/D-2/D-3 全部修完并实测闭合；两项补验完成；五道门全绿）

## 0. commits

| sha | 说明 |
|---|---|
| `576e19c3fc` | TASK-020：D-1 分量级闸门 + D-2 字符串可解析性/有限性闸门 + D-3 断言字段集下沉为共享 helper；4 个新 doctest；`DESIGN-DETAIL` §17.3 措辞；`scripts/mcp020_m4_defect_fixes_evidence.ps1` |
| 紧随 `576e19c3fc` 的那一条 | 本报告（`docs/reports/REPORT-020-m4-defect-fixes.md`）。**只新增报告文件**，不改任何源码/测试/脚本，因此本报告记录的门证据所依据的源码与 `576e19c3fc` 的树逐字节相同 |

**构建绑定（PLAYBOOK §3 的 R-1）**：所有门都在**提交后重建**的二进制上采集。

```
git rev-parse --short HEAD                      -> 576e19c3fc
bin\godot.windows.editor.x86_64.console.exe --version
                                                -> 4.8.dev.custom_build.576e19c3f   （前缀一致）
binary sha256                                   -> 3F48983DCB27E7B402BCE90561B9CE0E8121D905325D40883084B74308EE7093
构建命令：modules\mcp_server\scripts\build_local.cmd（= scons platform=windows target=editor
          module_mono_enabled=no tests=yes -j8），EXIT_CODE=0，日志 %TEMP%\mcp_server_build_local.log
改动 tests\test_mcp_server.h 后删除陈旧的 test_mcp_server / test_main 目标再构建（日志中可见
"Compiling modules\mcp_server\tests\test_mcp_server.cpp" 与 "Compiling tests\test_main.cpp"）
```

> 说明（避免误读）：构建发生在 `576e19c3fc` 之后，所以 `--version` 自报的正是该提交。本报告自身的提交
> 只会让版本戳**再次落后一行**（文档提交不改源码），这是 REPORT-017 §15.9 记录过的同一现象；门的对象
> 是「源码树」，而源码树在两次提交之间逐字节未变（见 §8 的文件 sha256 与 `git status`）。

---

## 1. 三个缺陷的修法与落点

### D-1（high）复合属性的**分量**绕过静默错值闸门

**修法**：`tools/running_game_node_write.cpp` 的 `shape_vector_from_json()` 在折叠前，把**每一个分量**
用 `MCPTools::coerce_to_property_type()` 按「该槽位自己的类型」过一遍：

| 目标类型 | 分量 | 分量类型 |
|---|---|---|
| `Vector2` | `x`,`y` | `FLOAT` |
| `Vector3` | `x`,`y`,`z` | `FLOAT` |
| `Color` | `r`,`g`,`b`,`a` | `FLOAT` |
| `Vector2i` | `x`,`y` | `INT` |
| `Vector3i` | `x`,`y`,`z` | `INT` |

- 不合规分量 → `-32602`，消息里的参数名带**分量路径**（`value.x` / `value[0].x`），调用方知道是哪一槽失败；
- 不是目标分量的成员（`{"x":1,"y":2,"spare":"ignored"}`）**原样保留**，`vector_from_dictionary` 照旧忽略它
  （线上实测 `D1_extra_key_ignored_like_the_engine_does` PASS，行为与修前一致）；
- `shape_vector_from_json` 同时补上**包装数组**的元素：`PackedVector2Array`/`PackedVector3Array`/
  `PackedColorArray` 的数组值里，对象元素走**同一张分量表**再折叠成向量，坏分量 `-32602`（`value[i].x`）；
- 校验发生在**任何写入之前**：`write_node_property` → `prepare_node_property_value` 与
  `editor_set_node_property_batch` 的写前预校验链都经过这一点，因此批量语义仍是**全成功或全回滚**。

**关于任务书指出的 `property_value_from_json` 递归点（一处显式偏离）**：`property_value_from_json` 的
`DICTIONARY` 分支递归传 `Variant::NIL` 是**有意的**，本次**保持不动**——该分支只保留 JSON 结构、**不做任何
折叠**，因此没有「分量类型」可判（`DICTIONARY` 属性合法地存字符串）；而 `DICTIONARY → VECTOR2` 在引擎
`Variant::can_convert` 里**是 false**（`VECTOR2` 的 valid 列表只有 `{VECTOR2I, NIL}`，`core/variant/variant.cpp:273-281`），
所以验收方给出的「整体转换是允许的」这一根因描述与实况不符：真正把 `"abc"` 静默折成 `0.0` 的是
`vector_from_dictionary` 里的 `(double)` 强转。修在**真正发生折叠的那一点**（`shape_vector_from_json`），
才让每个分量都过同一道门；这一处偏离在 §7 逐条列出。

**额外的容器元素闸门（超出任务书字面范围，主动收口同类面）**：`coerce_to_property_type` 对
`PACKED_INT32/INT64/BYTE/FLOAT32/FLOAT64/VECTOR2/VECTOR3/VECTOR4/COLOR/STRING_ARRAY` 目标、源为 `ARRAY`
时，把**每个元素**按元素类型再过一次本函数。于是
`[{"x":"abc","y":1}]`（PackedVector2Array）与 `["abc"]`（PackedFloat64Array）都是 `-32602`，
不再是 `(0,0)` / `0.0` 配 `code=0`。理由：这正是同一个「分量级静默错值」面（数组元素是它自己的复合值），
不修就等于把缺陷挪了一层；理由与残余面见 §6 R1/R2。

### D-2（high）`STRING → FLOAT/INT` 放行无法解析的字符串

**修法**：`coerce_to_property_type` 新增「字符串可解析性 + 有限性」判定（`_string_spells_number`）：

- `FLOAT` 目标：引擎自己的拼写判定 `String::is_valid_float()` **且** `String::to_float` 把整串**消费完**
  （`"1e"` 会把指数留在原地、结果是 `1`）**且**结果有限（`"1e999"` 在 `built_in_strtod` 里溢出成 `inf`）；
- `INT` 目标：`String::is_valid_int()`（整串除可选符号全是数字——`String::to_int("1e3")` 答案是 `1`，
  `"abc"` 答案是 `0`）**且**同一个 int64 范围守卫；
- 不合规 → `-32602`，消息点名「引擎自己的转换会给出默认值 0 而不是你发的值」，并给出可用的拼写示例；
- **保留 `#rrggbb` 的 Color 特例**（`STRING → COLOR` 是另一对，走引擎的转换关系，未触碰）；
- 可解析拼写照旧：`"1.5"`/`"-3"`/`"2e3"`（float）、`"7"`/`"-3"`（int）实测仍成功。

### D-3（medium）两个独立断言工具失败时不带 `reason`

**修法**：把**整份断言 verdict** 下沉为共享 field set（`tools/tool_helpers.cpp`）：
`node_state_assertion_fields()` / `screen_text_assertion_fields()`（外加
`node_assertion_failure_reason()` / `screen_text_failure_reason()` 两条文案生成路径）。两个入口都
**合并同一个对象**：

- 独立入口：`MCPTools::node_state_tool_verdict()` / `screen_text_tool_verdict()`
  （`tools/running_game_assertion.cpp`，工具直接把它当答案）；
- 场景运行器入口：`MCPTools::node_state_step_verdict()` / `screen_text_step_verdict()`
  （`tools/running_game_test_execution.cpp`，运行器只再加自己的 `type`/`step` 信封）。

修前/修后同一失败断言的线上形状（9889，逐字段）：

```
修前 tool : {"actual":"Main","assertion":"node_state","expected":"NotRoot","node_path":"/root/Main",
             "operator":"eq","passed":false,"property":"name"}                       <- 无 reason
修前 step : {...,"reason":"expected name eq NotRoot, found Main"}
修后 tool : {"actual":"Main","assertion":"node_state","expected":"NotRoot","node_path":"/root/Main",
             "operator":"eq","passed":false,"property":"name",
             "reason":"expected name eq NotRoot, found Main",
             "resolved_node_path":"/root/Main"}
修后 step : {"actual":"Main","assertion":"node_state","expected":"NotRoot","node_path":".",
             "operator":"eq","passed":false,"property":"name",
             "reason":"expected name eq NotRoot, found Main",
             "resolved_node_path":"/root/Main","step":0,"type":"assert"}
```

字段集比较（`key_diff_count=0`）：`[actual,assertion,expected,node_path,operator,passed,property,reason,resolved_node_path]`
两端**完全一致**；`reason` 逐字节相同。文本断言同理：
`[case_sensitive,expected_text,partial,passed,reason,source,visible_elements,visible_texts]`，
`reason="screen text containing 'NoSuchTextAnywhere' was not found in the 1 visible text(s) of the control tree"`。

**附加性字段变化（D-3 的一部分，需知悉）**：为了让两端真的是**一个**字段集，独立入口的节点断言新增
`resolved_node_path`，场景记录新增 `assertion` 与 `visible_elements`（文本断言）。三者都是**新增**键，
没有删除或改变任何既有键的语义；`node_path` 的两种含义（独立入口=解析后的路径，场景=step 里写的路径）
保持不变。

### §5 文档措辞修正（只改措辞）

`docs/DESIGN-DETAIL.md` §17.3 原文：「编辑器端点的期望集合是全体，游戏端点是『全体 − editor-only』」——
与它自己上一句的对称 scope 规则、门脚本（`accept_m1.ps1` 的 `$EditorToolNames = union − game-only = 91`）
和线上实况（9888=91 / 9889=53）不相容。改为：

```diff
-  维护第二份手写清单：把「所有 `implemented=true` 组的并集」按 `scope` 分成三类——editor-only、
-  game-only、both——编辑器端点的期望集合是全体，游戏端点是「全体 − editor-only」；已实现却属于
+  维护第二份手写清单：把「所有 `implemented=true` 组的并集」按 `scope` 分成三类——editor-only、
+  game-only、both——**两端点都用同一套对称规则推导**：编辑器端点的期望集合是「全体 − game-only」，
+  游戏端点是「全体 − editor-only」（`scope=both` 因此在两端都出现，两个端点各自排除的正是**只属
+  于另一端**的工具）；已实现却属于
```

**只改这段文字，不改任何规则**；`accept_m1.ps1`、`check_contract_subset.ps1` 未改动
（`accept_m1.ps1` sha256 仍为 `8d89a02bab8ea0a5f2bd92db616d3bde3502cfc46375b7ad57fdfc5b49a006d2`，与 M4 验收记录一致）。

---

## 2. 红/绿证据

### 2.1 doctest 红阶段（修前，模块用例）

命令：`bin\...console.exe --headless --test --test-case="[MCPServer]*"`，**退出码 1**

```
[doctest] test cases:  178 |  175 passed |   3 failed | 1429 skipped
[doctest] assertions: 7283 | 7182 passed | 101 failed |
[doctest] Status: FAILURE!
TEST CASE:  [MCPServer] TASK-020 D-1: a composite value's components pass the same gate      <- failed
TEST CASE:  [MCPServer] TASK-020 D-1: a packed array's elements pass the same gate           <- failed
TEST CASE:  [MCPServer] TASK-020 D-2: a string reaches a numeric property only when it spells a number  <- failed
（典型行）test_mcp_server.h(11924): ERROR: CHECK_FALSE( MCPTools::coerce_to_property_type(String(bad_ints[i]),
           Variant::INT, converted, error, "value") ) is NOT correct!  values: CHECK_FALSE( true )
          test_mcp_server.h(11925): ERROR: CHECK( error.code == -32602 ) is NOT correct!  values: CHECK( 0 == -32602 )
证据文件：%TEMP%\mcp020-evidence\gate3_red_doctest.txt
```

### 2.2 doctest 绿阶段（修后，绑定 HEAD 的二进制）

命令同上，**退出码 0**（`%TEMP%\mcp020-evidence-final\gate3_doctest.txt`）

```
[doctest] test cases:  179 |  179 passed | 0 failed | 1429 skipped
[doctest] assertions: 7312 | 7312 passed | 0 failed |
[doctest] Status: SUCCESS!
```

### 2.3 线上红阶段（修前，`-Phase pre`，9888/9889）

`%TEMP%\mcp020_pre_run.txt`（脚本同一份，逐条 PASS/FAIL）+ `%TEMP%\mcp020-evidence-pre\`

```
phase pre: 61 checks, 29 passed, 32 failed
[FAIL] D1_component_string_abc_x_...   :: code=0 result_is_null=False position={"x":0.0,"y":1.0}   <- 写进去了
[FAIL] D1_component_string_nan_y_...   :: code=0 result_is_null=False position={"x":1.0,"y":0.0}
[FAIL] D1_component_null_x_...         :: code=0 ... position={"x":0.0,"y":1.0}
[FAIL] D1_component_object_x_...       :: code=0 ... position={"x":0.0,"y":1.0}
[FAIL] D1_component_array_y_...        :: code=0 ... position={"x":1.0,"y":0.0}
[FAIL] D1_colour_component_refused     :: code=0 modulate={"a":1.0,"b":0.0,"g":0.0,"r":0.0}
[FAIL] D1_set_property_batch_refused_before_any_write :: code=0 Actor.position={"x":0.0,"y":1.0} Main.position={"x":0.0,"y":1.0}
[FAIL] D1_add_nodes_batch_component_refused_and_rolled_back :: code=0 ... MCP020BadA leaked=1
[FAIL] D2_rotation_string_refuse       :: code=0 rotation=0.0          <- M4 验收的原反例
[FAIL] D2_int_garbage_string_refused   :: code=0 z_index=0
[FAIL] D2_set_property_batch_string_refused :: code=0 Actor.rotation=0.0
[FAIL] D1_game_set_node_property_component_refused :: code=0 Actor.position={"x":0.0,"y":1.0}   <- 9889 同样
[FAIL] D2_game_set_node_property_string_refused    :: code=0 Actor.rotation=0.0
[FAIL] D3_node_tool_failure_carries_a_reason :: payload={...,"passed":false,"property":"name"}   <- 无 reason
[FAIL] D3_text_tool_failure_carries_a_reason :: payload={...,"passed":false,...}                 <- 无 reason
[FAIL] D3_node_entries_share_one_failure_field_set :: tool keys=[actual,assertion,expected,node_path,operator,passed,property]
[FAIL] D3_text_entries_share_one_failure_field_set :: tool keys=[case_sensitive,expected_text,partial,passed,source,visible_elements,visible_texts]
```

### 2.4 线上绿阶段（修后，`-Phase post`，绑定 HEAD 的二进制）

`%TEMP%\mcp020-evidence-final\gate2_evidence_post.txt`（stdout 副本，**注意**本 harness 的 stdout 捕获把每行截到
119 字符——见 §6 R5；完整证据串在脚本自己写出的
`%TEMP%\mcp020-evidence-post\results.json` 与每个请求的 `*.response.json` 里）

```
phase post: 67 checks, 67 passed, 0 failed
```

---

## 3. 证据形态：区分「拒绝」与「按引擎语义写默认值」

任务书 §3 的三条判据，本次每一条反例都**同时**覆盖（这正是 D67 的自检漏掉这两类的原因）：

| 判据 | 本次做法 | 绿阶段实测（完整值见 results.json） |
|---|---|---|
| ①错误码 | 必须 `-32602` 且 `result` 为 null | 全部反例 `code=-32602 result_is_null=True` |
| ②前后场景 `.tscn` sha256 相同 | 每个反例前 `Reset-Baseline`（写回已知值 → `editor_save_scene` → 记录 sha），反例后再 `editor_save_scene` 取 sha | `scenes/main.tscn sha_before=3f1fa258e20395f8e548b7b48a513796fc2655349208a3a4ac2815e6b268174e sha_after=3f1fa258…174e`（相同） |
| ③旧值仍为旧值 | 用**另一个读工具**读回并断言未被改动：9888 用 `editor_get_node_properties`，9889 用 `running_game_get_node_properties` | `Actor.position={"x":3.0,"y":4.0}`、`Actor.rotation=0.5`、`z_index=0`、`modulate={"r":1.0,"g":1.0,"b":1.0,"a":1.0}`（全部保持基线） |

典型的三条合成证据（绿阶段，逐字节选）：

```
D1_component_string_abc_x_refused_and_nothing_written
  code=-32602 result_is_null=True position={"x":3.0,"y":4.0} rotation=0.5
  sha_before=3f1fa258e20395f8e548b7b48a513796fc2655349208a3a4ac2815e6b268174e
  sha_after =3f1fa258e20395f8e548b7b48a513796fc2655349208a3a4ac2815e6b268174e
  message='Parameter 'value.x' is the string "abc" and a float property cannot take it: this engine's own
           text-to-number conversion (String::to_float) does not read that string as a number, so
           type_convert would answer a default (0) instead of the value you sent. ...'

D1_set_property_batch_refused_before_any_write
  code=-32602 Actor.position={"x":3.0,"y":4.0} Main.position={"x":0.0,"y":0.0} sha 相同
  message='Property 'position' write refused before any node was written: Parameter 'value.x' is the string "abc" ...'

D2_rotation_string_refuse
  code=-32602 rotation=0.5 position={"x":3.0,"y":4.0} sha 相同
  message='Parameter 'value' is the string "abc" and a float property cannot take it: ... (String::to_float) ...'
```

### 3.1 反例矩阵（六类值 + 复合 + 数组 + 批量）

**修后全部 `-32602` 且未写入**（每条都带 ②③；`D2_rotation_integer_accept` / `float_accept` 是回归正例）：

| 值类 | `rotation`（FLOAT） | 实测 | `z_index`（INT） | 实测 |
|---|---|---|---|---|
| 整数 | `3` | code=0，读回 3.0 ✅ | `3` | code=0 ✅ |
| 浮点 | `1.25` | code=0，读回 1.25 ✅ | — | — |
| 字符串 | `"abc"` | **-32602**，rotation 仍 0.5 ✅ | `"abc"` | **-32602**，z_index 仍 0 ✅ |
| 复合 | `{"z":9}` | **-32602**，rotation 仍 0.5 ✅ | — | — |
| 数组 | `[1,2]` | **-32602**，rotation 仍 0.5 ✅ | — | — |
| dictionary/null | `null` | **-32602**，rotation 仍 0.5 ✅ | — | — |
| 占位可解析字符串 | `{"x":"1.5","y":2}`（分量） | code=0 → `(1.5,2)` ✅ | `"7"` | code=0，z_index=7 ✅ |
| 越界字符串 | — | — | `"99999999999999999999"` / `"1.5"` | **-32602** ✅ |

`position`（`Vector2`，复合属性）：`"abc"` / `[1,2]` / `null` / `{"z":9}` 全部 **-32602** 且读回仍 `(3,4)`；
`"Vector2(1,1)"` 仍 **-32602**（TASK-019 P-1 的删除未回退）；`{"x":5,"y":6}` 仍 code=0 且读回 `(5,6)`。

五类坏分量 × 两个槽位（`x`/`y`），外加 `Vector3.z`、`Vector2i.x`、`Color.r`（后三者在 doctest 中钉住），
线上共 **10 条** `D1_component_*` 全 PASS；`modulate={"r":"abc","g":0,"b":0}` 亦 **-32602** 且 `modulate` 保持白。

**批量路径**（写前拒绝 + 全或无）：`editor_set_node_property_batch`（position 分量 / rotation 字符串）与
`editor_add_nodes_batch`（position 分量 / rotation 字符串）各 2 条，全部 `-32602`、`batch.status="rolled_back"`、
被拒元素**没有**出现在 `editor_find_nodes_by_type` 结果里、`.tscn` sha 相同。

---

## 4. 受影响工具清单（D-1/D-2 是**对已验收工具的行为变更**）

| # | 工具 | 共用的转换点 | 实测状态（本报告） |
|---|---|---|---|
| 1 | `editor_set_node_property` | `prepare_node_property_value` → `shape_vector_from_json` + `coerce_to_property_type` | **线上实测**：D-1 分量 10 条、Color 1 条、D-2 六类值与字符串/越界共 20+ 条 |
| 2 | `editor_set_node_property_batch` | 同上（写前预校验 + 逐节点 `write_node_property`） | **线上实测**：position 分量、rotation 字符串 |
| 3 | `editor_add_nodes_batch` | 同上（`write_node_property`） | **线上实测**：position 分量、rotation 字符串，均 rolled_back |
| 4 | `running_game_set_node_property`（9889） | 同上（`write_node_property`） | **线上实测**：position 分量、rotation 字符串、z_index `"9"` 可解析字符串 |
| 5 | `editor_add_resource_to_node_property` | 直接 `coerce_to_property_type(property_value_from_json(...))` | **线上实测**：`CanvasItemMaterial.light_mode="abc"` → -32602，`material` 未被替换 |
| 6 | `project_create_resource` | 同上 | **线上实测**：`Gradient.offsets=["abc"]` → -32602，**文件未创建**；合法 `[0.0,1.0]` 仍成功 |
| 7 | `project_edit_resource` | 同上 | **线上实测**：`Gradient.offsets=["abc"]` → -32602，文件 sha 相同 |
| 8 | `project_set_setting` | `shape_vector_from_json` + `coerce_to_property_type` | **线上实测**：int 设置给 `"abc"` → -32602，读回仍 5 |
| 9 | `project_set_node_property_across_scenes` | `prepare_node_property_value`（逐场景/逐节点） | **由共用点推导**（`project_cross_scene_write.cpp:332`）：坏值会被记进 `data.scenes.errors` 并整体拒绝。本报告只在**事务**层实测了它（§5.1 的 H1/H2/H3，用的是合法值 `z_index=5`），**未**单独构造「跨场景 + 坏分量」用例 |

> 第 1–8 项就是任务书列举的 7 个工具（外加 `project_set_setting`，它同样落在共享转换点上——D67 的清单里
> 没有它，但代码路径与实测都表明它是同一受影响面），全部**实测**；第 9 项**明确标注为推导**，不冒充实测。

---

## 5. 两项补验（M4 验收方未能完成的验证）

### 5.1 `project_set_node_property_across_scenes` 的多场景全或无事务（好文件 + 坏文件）

素材：`res://cross/one.tscn`（Node2D One）、`res://cross/two.tscn`（Node2D Two）、`res://cross/broken.tscn`
（`[gd_scene format=3]` 后接**截断**的节点行；在首次 `--import` 之后写入，避免污染导入日志）。

命令一律：`type=Node2D, property=z_index, value=5, path_filter=res://cross, force=true`。

| 检查 | 实测 |
|---|---|
| ①坏文件在场（`dry_run=false`） | `code=-32000`，`message='Refusing to write: 1 scene(s) of 'res://cross' cannot take this call'`，`data.scenes.errors=[{"reason":"not a loadable PackedScene","scene":"res://cross/broken.tscn"}]`，`data.suggestion='Nothing was written. Fix every file named in data.scenes.errors … and call again'`；**one.tscn / two.tscn 的 sha256 前后相同**（`0a33fd7f…cc4cc` / `198cd2a1…ed2b0`） |
| ②移除坏文件后 `dry_run=true` | `payload={"dry_run":true,"errors":[],…}`，`total_scenes/total_nodes` 已计划，磁盘 sha 未变 |
| ③移除坏文件后 `dry_run=false` | `payload={"dry_run":false,"errors":[],"editor_rescan_triggered":true,…}`，`total_scenes=2`；one.tscn / two.tscn 的 sha **都变了**（确实写入），`project_read_scene_file_content` 读回文本含 `z_index = 5` |

即：**坏文件在后 → 好文件未被改动（sha 相同）**、错误里带 `data.scenes.errors` 与「Nothing was written」形态、
**两个都好 → 都写入成功**，三条判据齐备。

### 5.2 `editor_analyze_screenshot_diff`（引擎自己编码的真实 PNG）

素材：`editor_execute_gdscript` 让**引擎自己**写两张 4×4 PNG（`Image.create` + `save_png`：
`res://diff_a.png` 全黑；`res://diff_b.png` 全黑且 `(1,1)` 为纯红），返回 `[4,4,4,4]`。

| 检查 | 实测 |
|---|---|
| 相同图 | `identical=true`、`changed_pixels=0`、`total_pixels=16`、`diff_percentage=0`、`width=4 height=4`、`diff_image_base64` 非空 |
| 不同图（默认 `threshold=10`） | `identical=false`、`changed_pixels=1`、`total_pixels=16`、`diff_percentage=6.25`、`threshold=10`、差异图 base64 非空 |
| 边界 | `threshold=255` → `identical=true, changed_pixels=0`（255 不算「大于 255」）；`threshold=0` → `changed_pixels=1` |
| 越界 | `threshold=300` → `-32602 "Parameter 'threshold' must be between 0 and 255 (it is a per-channel byte difference), got 300"`；`threshold=-1` → `-32602` |
| 缺参 | 少 `image_a` → `-32602 "Missing required parameter: image_a"` |

---

## 6. 残留风险与如实记录（未修改项）

- **R1（残余面，低）**：容器元素闸门按元素**Variant 类型**判定，没有做元素**位宽**判定——`PackedByteArray`
  的元素是 `INT`，`300` 能通过闸门（类型层面合法）；`PackedInt32Array` 同理只查 int64 范围。这与标量
  `int` 属性的既有语义一致（`property_type_of` 只给 `INT`），属**既有**语义，本次未扩大范围。
- **R2（残余面，低）**：`PackedVector4Array` 的元素没有「对象 → 向量」整形（`vector_from_dictionary` 没有
  `Vector4` 分量表）——对象元素被元素闸门**响亮拒绝**（`DICTIONARY → VECTOR4` 不在转换关系里），**不是**
  静默零值。要支持它需要给 `vector_from_dictionary` 加第四张表，超出任务书范围。
- **R3（观察，未修）**：`STRING → BOOL` 仍是「引擎可转换」的一对（`type_convert("abc", BOOL)` 给出真值），
  与 D-2 同类的「字符串可解析性」问题在 BOOL 上依然存在。D-2 的任务边界是 `FLOAT/INT`，本次**没有**扩展；
  记录在案供决策层判断是否需要下一轮任务。
- **R4（措辞，未修）**：`editor_add_resource_to_node_property` 的拒绝消息里参数名是字面量
  `'resource_properties'`（不带到具体子键），故线上消息形如
  `Parameter 'resource_properties' is the string "abc" and a int property cannot take it`。这是既有措辞
  （`editor_write_scene_editor.cpp:662` 传入的 `p_parameter_name`），不是本次引入；**元素**级消息已带索引
  （`value[0]` / `properties[0]`）。
- **R5（证据载体，harness 现象）**：本 harness 对后台作业的 **stdout 捕获把每行截到 119 字符**，因此
  `%TEMP%\mcp020-evidence-final\*.txt` 的**长证据串被截断**，且 PowerShell `*>` 重定向写的是 **UTF-16LE**。
  权威证据是脚本**自己写盘**的 `results.json`（完整字符串）与每个请求的 `*.response.json`（原始响应体）；
  报告中的所有 sha256/消息都取自 `results.json`。建议后续任务书把「后台作业 stdout 会被截断」写进门纪律。
- **R6（流程）**：§2.3 的 pre 证据是用**同一脚本的上一修订版**跑的（pre 有 `D1_baseline_restored`，
  post 有 `D2_int_out_of_range_string_refused`，其余 60 个 check id 完全相同）。两版之间唯一的差别是
  「每条用例先重置基线」这一加强（使每条判据独立）与新增那一条越界检查；缺陷复现本身未受影响。
- **R7（流程）**：本报告的提交会让二进制的版本戳落后 HEAD 一行（文档提交不改源码）；§0 已给出绑定说明。

---

## 7. deviations（与手册/任务书的任何偏离，逐条显式列出）

1. **D-1 的落点**：任务书写「递归时携带目标分量类型」（指向 `property_value_from_json` 的 `DICTIONARY`
   递归），本实现把分量闸门放在**真正折叠分量**的 `shape_vector_from_json` / `_check_components`，
   并**保留** `property_value_from_json` 递归的 `Variant::NIL`（该分支不折叠任何值）。理由与实测根因
   见 §1-D-1；任务书给出的根因描述（「dict→Vector2 整体转换是允许的」）与引擎实况不符——
   `can_convert(DICTIONARY, VECTOR2)` 为 **false**（`core/variant/variant.cpp:273-281`）。
2. **主动扩大范围（容器元素闸门）**：在 `coerce_to_property_type` 增加了 packed 容器目标的**元素**闸门，
   并把 packed 向量数组的**对象元素**整形接进 `shape_vector_from_json`。任务书未要求，但不修就是同一缺陷
   的另一层（数组元素）；残余面已在 §6 R1/R2 标注。
3. **D-3 的字段集统一带来三个新增键**：独立入口节点断言加 `resolved_node_path`，场景记录加 `assertion`
   与 `visible_elements`（文本）。均为新增，未删除/改写既有键语义。
4. **D-2 比字面要求更严一点**：INT 目标**拒绝**小数拼写（`"1.5"`），修前它会经 `String::to_int` 得到 `1`。
   任务书只要求「不可解析/非有限 → -32602」；本条属于「可解析性」的严格读法，已在 doctest（
   `D2_int_fractional_string_refused`）与线上（`D2_int_fractional_string_refused`）双双钉住。
5. **额外添加了一个工具面检查**：`project_set_setting` 不在 D67 的 7 工具清单里，但同属共享转换点，
   已实测并列进 §4（第 8 项）。
6. **pre 证据用上一修订版脚本**（§6 R6）。
7. **未修改 `accept_m1.ps1` / `check_contract_subset.ps1` / 任何契约或映射文件**（除 §1-§5 的
   `DESIGN-DETAIL.md` 措辞外，未改规范）。

**blockers**：无。

---

## 8. 五道门（全部在绑定 `576e19c3fc` 的二进制上、串行、未抑制输出）

| 门 | 命令 | 结果 | 退出码 | 证据 |
|---|---|---|---|---|
| ① 契约子集逐字 | `scripts\check_contract_subset.ps1 -Group running_game_assertion` | `editor_9888_contract_subset` PASS、`game_9889_contract_subset` PASS、`guard_user_port_9877` PASS；`implemented_union=91 tools (editor endpoint) / 53 tools (game endpoint)`；本组 3 条 `name/description/inputSchema` 逐字 True | **0** | `%TEMP%\mcp020-evidence-final\gate1_contract_subset.txt` |
| ② 三类证据 + 反例矩阵 + 两项补验 | `scripts\mcp020_m4_defect_fixes_evidence.ps1 -Phase post` | **67/67 checks PASS**（修前同一脚本：61 checks / 29 passed / **32 failed**） | **0** | `…\gate2_evidence_post.txt`、`%TEMP%\mcp020-evidence-post\results.json`、`…\*.request.json` / `*.response.json` |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **179 cases / 179 passed / 0 failed**；**7312 assertions / 7312 passed / 0 failed**（基线 175/175·7122，只增不减） | **0** | `…\gate3_doctest.txt` |
| ④ 全引擎回归 | `--headless --test` | **1605 cases / 1605 passed / 0 failed / 3 skipped**；**431594 assertions / 431594 passed / 0 failed**（基线 1601/1601·431404） | **0** | `…\gate4_full_test.txt` |
| ⑤ 批收口 | `scripts\accept_m1.ps1` **连跑两次** | 两次均 **22/22 cases passed**；两次 PASS 清单 `Compare-Object` **diff = 0**（22 行） | **0 / 0** | `…\gate5_accept_run1.txt`、`…\gate5_accept_run2.txt` |

补充机器校验（与 M4 验收同一组，实况未变）：

```
python docs\scripts\check_tool_groups.py                    -> EXIT=0  TOOL-GROUPS CHECK PASS
python docs\scripts\check_tool_groups.py --batch B3         -> EXIT=0  TOOL-GROUPS-B3 CHECK PASS
python docs\scripts\check_tool_groups.py --batch B4         -> EXIT=0  TOOL-GROUPS-B4 CHECK PASS
python docs\scripts\check_tool_groups.py --check-completeness -> EXIT=0 TOOL-GROUPS-COMPLETENESS CHECK PASS
```

**端口纪律**：全程只用 9888/9889；9877 的 owner 在每次运行的开工/收尾采样均为用户进程 **PID 36392**
（`guard_user_port_9877` 在门①、门⑤中亦 PASS）；收尾后 9888/9889 均 owner=-1。**未占用、未杀、未重启 9877**。

**工作树终态**：`git status --short` 仅 4 个**既有**未跟踪项（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、
`install-deps-m0.cmd`）；本次未执行任何 **push**。

### 8.1 本次改动的文件 sha256（工作树 = `576e19c3fc` 的树）

```
files  -------------------------------------------------------------------
f5d716ac4a874e854ee26bd0a16f1977e18dec3f3c5fa08387eab30f640fe581  modules/mcp_server/scripts/mcp020_m4_defect_fixes_evidence.ps1
ab801565df9ab17706c786fbbc5ea889f9b803a1270bd39f213b538564aaf40d  modules/mcp_server/tools/tool_helpers.h
2a290d3ed8712744d9d3d7c578284e22ead8d5ce7175d50c0428358aeed4de9d  modules/mcp_server/tools/tool_helpers.cpp
1c52d0748563c66b0de7f4a1dad15dd4cc7157e1d875b0919f38f4a4f68bb5a9  modules/mcp_server/tools/running_game_node_write.h
4367789c4c9497e00d4229fbaded9baf1fe8c7fbd560f4a39e242674e3fbded9  modules/mcp_server/tools/running_game_node_write.cpp
00fe2a7be489fbb7bb6c0f17f9ebb25d38d1155e9a082789a945d7f8636cb16a  modules/mcp_server/tools/running_game_assertion.h
cd3b7c5b329f862ec522fc06c9b198c15cfc2e49280243bacf30574f56db5bea  modules/mcp_server/tools/running_game_assertion.cpp
9b57f04c11934a1d2f06ac1b858c6fabd9d3e9213008848eec9c49214fe063cc  modules/mcp_server/tools/running_game_test_execution.h
5030a04a0ba88d2f4ce2ae2a6ec6fec14ef9cefc6b567feb4fc643c533afeaf5  modules/mcp_server/tools/running_game_test_execution.cpp
a4a410f597430541e8267f7d67081884f1b0a933da723da16187d65f5f311e8a  modules/mcp_server/tests/test_mcp_server.h
29426a68465b9291bbee8c806f32c1a080d6074ef867d97adfe06fa759b749ac  modules/mcp_server/docs/DESIGN-DETAIL.md
8d89a02bab8ea0a5f2bd92db616d3bde3502cfc46375b7ad57fdfc5b49a006d2  modules/mcp_server/scripts/accept_m1.ps1            （未改动）
3a66b9cd08576b1cd3ec4b20fbba4c418367779b556142852e53b47491f467c8  modules/mcp_server/scripts/check_contract_subset.ps1（未改动）
binary -------------------------------------------------------------------
3F48983DCB27E7B402BCE90561B9CE0E8121D905325D40883084B74308EE7093  bin/godot.windows.editor.x86_64.console.exe（--version = 4.8.dev.custom_build.576e19c3f）
```

### 8.2 新增/改动的测试

`tests/test_mcp_server.h` 的 `namespace Task020`（+407 行）：

| 用例 | 钉住什么 |
|---|---|
| `[MCPServer] TASK-020 D-1: a composite value's components pass the same gate` | 5 类坏分量 × 2 槽位 → `-32602` 且消息带 `value.x`/`value.y`；Vector3/Vector2i/Color 同一张表；数值/整型浮点/可解析字符串/缺省 alpha 的正例；CR-1 的「没给分量」拒绝不变 |
| `[MCPServer] TASK-020 D-1: a packed array's elements pass the same gate` | 数组元素对象的分量闸门（`value[0].x`）；合法对象元素被整形为真向量并转成 `PackedVector2Array`；无整形步骤的 `coerce` 路径**响亮拒绝**；`["abc"]` → `-32602`，`["1.5",2]` 仍成功 |
| `[MCPServer] TASK-020 D-2: a string reaches a numeric property only when it spells a number` | 13 个坏 float 拼写 / 6 个坏 int 拼写 → `-32602`；4/5 个可解析拼写的值；`#rrggbb` 与 String 属性不受影响；`"Vector2(1,2)"` 仍拒绝 |
| `[MCPServer] TASK-020 D-3: the two assertion entries share one failure field set` | 两个入口的**失败字段集逐键相同**、`reason` 逐字节相同、字段集清单逐字比对；通过时都不带 `reason`；期望值按比较时的形状回显；文本断言的搜索空间（`visible_texts`/`visible_elements`）两端一致 |

---

## 9. next_step_recommendation

1. **派全新验收子代理独立复核**：至少重跑 (a) M4 验收的 C7g/C7h 五种分量值与字符串值，(b) 批量事务段，
   (c) 本报告 §3 的三条证据形态（错误码 + `.tscn` sha256 + 另一个读工具读回的旧值），(d) §5 的两个补验项，
   (e) §8 的门②~⑤（用 `build_local.cmd`（`tests=yes`）重建并校验 `--version` == HEAD）。
2. **决策层裁定 §6 的残余面**：R3（`STRING → BOOL` 的同类可解析性问题）与 R1/R2（容器元素位宽、`Vector4`
   元素整形）是否值得下一轮任务；这三项都是**响亮/模型内**行为，不存在「静默写默认值」。
3. **规范补强建议**：把「后台作业 stdout 会被截断到 119 字符、且 `*>` 重定向是 UTF-16LE」写进
   PLAYBOOK §7（证据采集纪律），并要求证据脚本**自己**写一份完整 transcript（本次靠 `results.json`
   兜底，可用但绕）。
4. **任务书措辞建议**：D-1 的根因描述可更新为「`vector_from_dictionary` 的 `(double)` 强转折叠分量」
   （`can_convert(DICTIONARY, VECTOR2)` 实为 false），以免下一位执行者按错误的根因去找修法。