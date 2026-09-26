# REPORT-021 — TASK-021：静默错值的**同类残留面**补齐（STRING→BOOL / 容器元素与分量位宽 / Vector4 整形 / STRING→COLOR）

- 任务书：`docs/tasks/TASK-021-remaining-silent-value-surfaces.md`（规范：`docs/tasks/PLAYBOOK-group-port.md`）
- 执行者：实现工程师（**未参与** M4 验收；本报告全部结论均由本次自行运行产生）
- 日期：2026-09-22
- 仓库：`F:\RustProjects\godot-mcp-pro\code\godot`（分支 `feature/mcp-server-module`）
- `status`：**完成**（4 个面 + 1 个顺带发现面全部修完并实测闭合；同类面清单给出并逐条判定；五道门全绿）

## 0. commits

| sha | 说明 |
|---|---|
| `de04c86f4c` | TASK-021：关闭残留的静默错值面（STRING→BOOL、packed 元素位宽、分量位宽、Vector4 分量表、STRING→COLOR）；5 个新 doctest；`scripts/mcp021_remaining_silent_value_surfaces_evidence.ps1`；`project_set_setting` 接受 `PackedVector4Array` |
| 紧随 `de04c86f4c` 的那一条 | 本报告（`docs/reports/REPORT-021-remaining-silent-value-surfaces.md`）。**只新增报告文件**，不改任何源码/测试/脚本，因此本报告的门的对象与 `de04c86f4c` 的树逐字节相同 |

**构建绑定（PLAYBOOK §3 的 R-1）**：全部门都在**提交 `de04c86f4c` 之后重建**的二进制上采集，且校验通过。

```
git rev-parse --short HEAD                      -> de04c86f4c
bin\godot.windows.editor.x86_64.console.exe --version
                                                -> 4.8.dev.custom_build.de04c86f4   （前缀一致）
binary sha256                                   -> CAA3C690E4454FF28B6453D1BD80934B09B9F571CFCD32D6252045E40664EB0C
构建命令：modules\mcp_server\scripts\build_local.cmd（= scons platform=windows target=editor
          module_mono_enabled=no tests=yes -j8），REBUILD_EXIT=0，日志 %TEMP%\mcp_server_build_local.log
改 tests\test_mcp_server.h 后删除陈旧的 test_mcp_server / test_main 对象再构建（日志中可见
"Compiling modules\mcp_server\tests\test_mcp_server.cpp" 与 "Compiling tests\test_main.cpp"）
```

> 说明：本报告自身的提交只会让版本戳**再次落后一行**（文档提交不改源码），这是 REPORT-017 §15.9 / REPORT-020 §0
> 记录过的同一现象；门的对象是「源码树」，源码树在两条提交之间逐字节未变（见 §9 的文件 sha256）。

---

## 1. 修法、落点与「修前红」

四条面都是同一族：**一个 JSON 值在目标类型里表达不出来，引擎的转换给出一个默认值，工具回 `code=0`**。
每条都先用线上证据（§2.3）与 doctest（§2.1）复现，再修。

### A-1（high）`STRING -> BOOL`：每个非空字符串都是 `true`

- **根因**：`Variant::can_convert(STRING, BOOL)` 为 **true**（`core/variant/variant.cpp:233-242`），转换落到
  `Variant::booleanize()` = `!is_zero()`（`core/variant/variant_op.cpp:1116-1124`），而 STRING 的 `is_zero()` 是
  「等于空串」（`variant.cpp:922-924`）。因此 `"abc"`、`"false"`、`"0"`、`" "` 全部写成 `true`。
- **修法**（`tools/tool_helpers.cpp` 的 `coerce_to_property_type`，新增 `_string_spells_bool`）：只有
  `"true"/"false"/"1"/"0"`（两个单词大小写不敏感）被接受，且**写入的值是拼写所指的布尔**（不经过
  `type_convert`——它对 `"false"` 会回 `true`）。其余（`"abc"`、`""`、`"yes"`、`"2"`、`"true "`…）→ `-32602`。
- **与引擎语义的显式分歧**：`booleanize("0")` 是 `true`（非空串），本实现把它当 `false`（拼写所指）。理由：给
  `"0"` 写 `true` 正是本闸门要消灭的静默错值；分歧记入 §8 偏离 1。

### A-2（high）packed 容器**元素位宽**：类型对、宽度不够

- **根因**：TASK-020 的元素闸门判的是元素 **Variant 类型**（INT/FLOAT/VECTOR2…），而元素最终被复制进的
  C++ 槽位更窄：`PackedByteArray -> Vector<uint8_t>`（`Variant::operator uint8_t()` 是 `static_cast`）、
  `PackedInt32Array -> Vector<int32_t>`、`PackedFloat32Array -> Vector<float>`。
- **修法**（`tool_helpers.cpp` 新增 `_element_fits_container`，在 `coerce_to_property_type` 的 ARRAY 分支
  逐元素判定）：
  - `PackedByteArray`：元素必须落在 `0..255`；
  - `PackedInt32Array`：元素必须在 int32 范围；
  - `PackedFloat32Array`：元素转 float 后必须有限（`1e300` 曾是 `inf`），且非零值不能下溢成 `0`（`1e-300`）；
  - `PackedInt64Array` / `PackedFloat64Array`：槽位就是闸门已判的类型，无新增判定。
  越界 → `-32602`，消息点名 `value[i]` 并**写出引擎本来会写的值**（`44` / `-1294967296` / `inf`）。
- 任务书提到 `1e20`：实测它**在修前就已被拒**（TASK-020 的 int64 范围守卫，`Parameter 'value[0]' is outside the
  range of a 64-bit integer`），修后不变。

### A-3（medium）`PackedVector4Array` 等向量数组的**元素整形**缺 `Vector4`

- **根因**：`_container_element_type` 已知 `PACKED_VECTOR4_ARRAY -> VECTOR4`，但元素整形步骤
  `shape_vector_from_json`（`_packed_vector_element_type`）没有 `PACKED_VECTOR4_ARRAY`，`vector_from_dictionary`
  也没有 `Vector4` 分量表；于是对象元素**响亮拒绝**（不是静默零值），但同一张分量表覆盖不到它。
- **修法**（`tools/running_game_node_write.cpp`）：`vector_from_dictionary` / `vector_component_hint` /
  `_vector_components` / `_packed_vector_element_type` 四处补 `Vector4`（`x,y,z,w` 皆为 `FLOAT`）。修后
  `[{"x":1,"y":2,"z":3,"w":4}]` 被整形并打包；坏分量 `value[0].x`、缺 `w` 都是 `-32602`。
- 为使该面**线上可构造**：`project_set_setting` 的接受类型表补 `PackedVector4Array`（该工具的拒绝消息本来就
  写着「the Packed*Array family」，唯独漏了这一个成员）。见 §8 偏离 3。

### A-4（high）**分量**位宽：`real_t` 槽与 int32 槽

- **根因**：分量闸门判 `FLOAT`/`INT`，但成员更窄：`Vector2/3/4`、`Color` 的分量是 `real_t`（本构建
  `precision` 默认 `single`，`SConstruct:192` → **float**），`Vector2i/Vector3i` 的分量是 `int`（32 位），
  `vector_from_dictionary` 的 `(double)`/`(int)` 强转静默收窄。
- **修法**（`running_game_node_write.cpp` 的 `_VectorComponent` 增加 `_ComponentWidth` 字段 +
  `_component_fits_slot`，在 `_check_components` 里对已过闸的分量再判一次）：float 槽要求

  转 float 后有限且不下溢成 0；int32 槽要求落在 int32 范围。越界 → `-32602`，点名 `value.x`。
  `REAL_T_IS_DOUBLE` 构建下 float 槽判定被编译掉（宽类型无需判）。

### A-5（high，**读通代码**时新发现的面）`STRING -> COLOR`：读不出的颜色串写成黑

- **根因**：`can_convert(STRING, COLOR)` 为 true，转换落到 `Color(const String &)`
  （`core/math/color.h:277-283`）= 「`html_is_valid` ? `html` : `named`」，而 `Color::named()` **没有默认值**时是
  `ERR_FAIL_V_MSG(Color(), ...)`（`color.cpp:396-402`）→ `Color(0,0,0,1)`。实测 `modulate: "notacolor"` 与
  `modulate: ""` 都回 `code=0` 并写入黑色。
- **修法**：在 `coerce_to_property_type` 里对 `STRING -> COLOR` 先问引擎自己的两个语法
  （`Color::html_is_valid` 或 `Color::find_named_color != -1`，后者与 `named()` 用的是同一个查表与
  `remove_chars(" -_'.")`+大写归一化），都不是 → `-32602`；`INT -> COLOR`（`Color::hex`）是另一对，未触碰。

---

## 2. 红/绿证据

### 2.1 doctest 红阶段（修前，模块用例）

命令：`bin\...console.exe --headless --test --test-case="[MCPServer]*"`，**退出码 1**

```
[doctest] test cases:  184 |  179 passed |   5 failed | 1429 skipped
[doctest] assertions: 7508 | 7385 passed | 123 failed |
[doctest] Status: FAILURE!
TEST CASE:  [MCPServer] TASK-021 A-1: a string reaches a bool property only when it spells a boolean   <- failed
TEST CASE:  [MCPServer] TASK-021 A-2: a packed container's element has to fit the element width        <- failed
TEST CASE:  [MCPServer] TASK-021 A-3: a Vector4 element goes through the same component table          <- failed
TEST CASE:  [MCPServer] TASK-021 A-4: a component has to fit the width of the slot it fills            <- failed
TEST CASE:  [MCPServer] TASK-021 A-5: a string reaches a colour property only when the engine can read it  <- failed
（典型行）test_mcp_server.h(12116): ERROR: CHECK_FALSE( MCPTools::coerce_to_property_type(String(bad[i]), Variant::BOOL,
           converted, error, "value") ) is NOT correct!  values: CHECK_FALSE( true )
          test_mcp_server.h(12117): ERROR: CHECK( error.code == -32602 ) is NOT correct!  values: CHECK( 0 == -32602 )
证据文件：%TEMP%\mcp021-evidence\red_doctest.txt
```

> **修订说明（append-only 勘误）**：红阶段跑的是本报告最终测试修订版**之前**的一版，两处**对照**断言的期望字面量
> 当时写错（`DodgerBlue` 手写 `0.117647f` 与 `Color::hex` 的浮点值不逐位相等；`Color::hex(0xff0000)` 我按 RGBA
> 读、引擎按 A/B/G/R 低字节优先读，实为 `(0,1,0,0)`）。这两条是**正例对照**、不是缺陷断言：它们在红阶段失败
> 只因字面量写错，在最终修订版的红阶段会通过（转换本身在修前就工作）。A-5 这个 case 在红阶段另有 8×3 条**缺陷
> 断言**失败（坏颜色串被放行）。除此之外，报告中的所有红证据（含 §2.3 的线上红）都是最终修订版产生。

### 2.2 doctest 绿阶段（修后，绑定 `de04c86f4c` 的二进制）

命令同上，**退出码 0**（`%TEMP%\mcp021-evidence\gate3_doctest_modular.txt`）

```
[doctest] test cases:  184 |  184 passed | 0 failed | 1429 skipped
[doctest] assertions: 7509 | 7509 passed | 0 failed |
[doctest] Status: SUCCESS!
```

基线（REPORT-020）：`179 cases / 179 passed`、`7312 assertions`；本任务只增不减（+5 cases、+197 assertions）。

### 2.3 线上红阶段（修前 `-Phase pre`，9888/9889；最终脚本修订版）

`%TEMP%\mcp021-evidence-pre\results.json`、`summary.json`，**退出码 1**

```
phase pre: 74 checks, 40 passed, 34 failed
```

修前实测（逐条节选，全部 `code=0` 且真的写进去了）：

| 面 | check | 修前实况 |
|---|---|---|
| A-1 | `B1_bool_bad_1..8` | `visible:"abc"/"yes"/"no"/"2"/"-1"/"true "/"0.0"` → `visible=true`；`""` → `visible=false` |
| A-1 | `B2_bool_spelling_false/0` | `visible:"false"` → `visible=**true**`；`visible:"0"` → `visible=**true**` |
| A-2 | `C2_byte_element_300` | `PackedByteArray [300]` → 设置变成 `"[44]"` |
| A-2 | `C2_byte_element_minus1` | `[-1]` → `"[255]"` |
| A-2 | `C2_byte_element_1e20` | 修前已 `-32602`（int64 范围守卫），非红项 |
| A-2 | `D2_int32_element_3e9` | `PackedInt32Array [3000000000]` → `"[-2147483648]"` |
| A-2 | `E2_float32_element_1e300` | `PackedFloat32Array [1e300]` → `"[inf]"` |
| A-2 | `E2_float32_element_1e_minus300` | `[1e-300]` → `"[0.0]"` |
| A-3 | `G1_vector4_object_element_still_writes` | `type='PackedVector4Array'` 被拒：「names no type this tool can write」 |
| A-5 | `H2_colour_unreadable_string` | `Color` 设置 `"#ff0000"` 后 `"notacolor"` → 写黑 `{"r":0,...}` |
| A-5 | `L1_modulate_unreadable_string` / `_empty_string` | `Actor.modulate` 变黑 |
| A-4 | `J1_component_float32_overflow_position` | `position={"x":1e300,"y":1}` → `code=0`（读回工具随后答不出 payload——JSON 序列化 `inf` 失败） |
| A-4 | `J1_component_float32_overflow_modulate` | `modulate={"b":1e300}` → `code=0` |
| A-2/A-4 | `I1_/I3_/I4_` | `project_create_resource` `Gradient.offsets=[1e300]` 与 `AudioStreamWAV.data=[300]` **建出了文件**；`project_edit_resource` 写入成功 |
| 批量 | `K1_/K2_` | `editor_set_node_property_batch`（`visible:"abc"`、`modulate:"notacolor"`）→ `code=0` 并写进去 |
| 批量 | `K3_/K4_/K5_` | `editor_add_nodes_batch` 三个坏值节点**被创建且泄漏**（`leaked=1`），`.tscn` sha 改变 |
| 9889 | `N1_/N3_/N9_` | 游戏端点同样：`visible:"abc"`→true、`modulate:"notacolor"`→黑、`visible:"false"`→true |

### 2.4 线上绿阶段（修后 `-Phase post`，绑定 `de04c86f4c`）

`%TEMP%\mcp021-evidence-post\results.json`、`summary.json`，**退出码 0**

```
phase post: 74 checks, 74 passed, 0 failed
```

典型的三条合成证据（每一条都**同时**带 ①错误码 ②文件 sha256 相同 ③另一读工具读回旧值）：

```
B1_bool_bad_1
  code=-32602 result_is_null=True position={"x":3.0,"y":4.0} rotation=0.5 visible=true
  sha_before=e774f90b67463b83a43121d91cebd871073c07624dab8148a7b6ea6336e9314d
  sha_after =e774f90b67463b83a43121d91cebd871073c07624dab8148a7b6ea6336e9314d
  message='Parameter 'value' is the string "abc" and a bool property cannot take it: this engine's own
           text-to-bool conversion (Variant::booleanize) answers true for every non-empty string, ...'

C2_byte_element_300
  code=-32602 type='PackedByteArray' setting_before="[1, 2]" setting_after="[1, 2]"
  project.godot sha_before=70d8a07fb99a420bff83163367f272182bea8dad2575c7459b706ed81322abab
              sha_after =70d8a07fb99a420bff83163367f272182bea8dad2575c7459b706ed81322abab
  message='Parameter 'value[0]' is the integer 300, which does not fit in the 8-bit unsigned element a
           PackedByteArray stores: ... would write 44 instead of the value you sent. Send an integer between 0 and 255.'

J1_component_float32_overflow_position
  code=-32602 result_is_null=True position={"x":3.0,"y":4.0} sha 相同
  message='Parameter 'value.x' is the number 1e+300, which does not fit in the 32-bit float component this
           build's single-precision real_t stores: ... would write inf ...'
```

### 2.5 反例矩阵（九类值 + 复合/数组/容器/dictionary/null + 批量）

**修后**（每条都带 ②③；接受项是回归正例）：

| 值类 | 目标 | 反例 → 实测 |
|---|---|---|
| 整数 | `PackedByteArray` / `PackedInt32Array` | `300` / `3000000000` → **-32602**，设置与 `project.godot` sha 不变 ✅ |
| 浮点 | `PackedFloat32Array` | `1e300`、`1e-300` → **-32602** ✅ |
| 字符串 | `bool`（`visible`） | `"abc"`、`""`、`"yes"`、`"no"`、`"2"`、`"-1"`、`"true "`、`"0.0"` → **-32602**，`visible` 仍为 `true` ✅ |
| 字符串（可解析） | `bool` | `"false"`→`false`、`"0"`→`false`、`"true"`→`true`、`"1"`→`true`（**不是** `type_convert` 的答案） ✅ |
| 字符串 | `Color`（`modulate`、Color 设置） | `"notacolor"`、`""`、`"#zzzzzz"`、`"#12345"`、`"0xff0000"` → **-32602** ✅ |
| 字符串（可解析） | `Color` | `"#ff0000"`→红、`"#f00"`→红、`"#ff00"`→`Color(1,1,0,0)`、`"red"`/`"DodgerBlue"`/`"abc"`（三位十六进制） ✅ |
| 复合 | `Vector2`/`Color` 分量 | `{"x":1e300}`、`{"b":1e300}` → **-32602**，点名 `value.x`/`value.b` ✅ |
| 复合 | `Vector2i` 分量 | `{"x":3000000000}` → **-32602**，点名 `value.x` ✅ |
| 复合 | `Vector4` / `PackedVector4Array` 元素 | `{"x":"abc",...}` → **-32602** `value[0].x`；缺 `w` → **-32602** 组件清单；合法对象 → 打包成功 ✅ |
| dictionary/array/null | `bool`（`visible`） | `null`、`[1,2]`、`{"a":1}` → **-32602**，`visible` 不变 ✅ |
| 容器 / 资源写手 | `Gradient.offsets`、`AudioStreamWAV.data` | 文件**未创建** / `.tres` sha 不变 ✅ |
| 批量（3 条路径） | `editor_set_node_property_batch`、`editor_add_nodes_batch` | `-32602` + `batch.status="rolled_back"` + 节点未泄漏 + `.tscn` sha 相同 ✅ |

---

## 3. 值转换路径清单（任务书 §1.4：修 / 不修 + 理由）

**自查范围**：模块里**一切把 JSON 值写进有类型槽位**的路径。由调用图枚举（`coerce_to_property_type` /
`prepare_node_property_value` / `write_node_property` / `->set(` 的全部调用点），共三个入口：

- `running_game_node_write.cpp` 的 `prepare_node_property_value`（节点/资源对象的写，`editor_set_node_property`、
  `editor_set_node_property_batch`、`editor_add_nodes_batch`、`editor_add_nodes`、`editor_setup_*`、
  `project_set_node_property_across_scenes`、`running_game_set_node_property`）；
- `project_write_resource_scene.cpp:230/463` 与 `editor_write_scene_editor.cpp:662` 的**直接**
  `coerce_to_property_type(property_value_from_json(...))`（`project_create_resource`、`project_edit_resource`、
  `editor_add_resource_to_node_property`）；
- `project_setting_write.cpp` 的 `set_project_setting`。

JSON 边界能产生的源类型只有 `NIL/BOOL/INT/FLOAT/STRING/ARRAY/DICTIONARY`（`property_value_from_json` 的入参
永远是 JSON），因此 `OBJECT/RID/CALLABLE/...` 那些 `Variant::operator <T>()` 的 `else` 默认值**不可达**。

| # | 路径 | 判定 | 理由 / 证据 |
|---|---|---|---|
| 1 | `STRING → FLOAT/INT` | **已修（TASK-020 D-2）** | `"abc"`/`"1e3"` 曾静默成 `0`/`1`；现按引擎解析器判「整串是否拼出一个数」 |
| 2 | `STRING → BOOL` | **本次修（A-1）** | `booleanize()` 对每个非空串回 true；现只接受四种拼写并写拼写所指的值 |
| 3 | `STRING → COLOR` | **本次修（A-5，顺带发现）** | `Color(String)` 对读不出的串回黑；现按 `html_is_valid`/`find_named_color` 判 |
| 4 | `STRING → STRING/STRING_NAME/NODE_PATH` | **不修** | 由文本构造，**没有失败模式**（`NodePath(String)`、`StringName(String)` 恒成功） |
| 5 | `STRING → VECTOR*/RECT*/...` | **不修（已安全）** | `can_convert` 为 false → TASK-018 闸门已 `-32602`（`"Vector2(1,2)"` 即此例） |
| 6 | `ARRAY → PACKED_*` 的**元素类型** | **已修（TASK-020 D-1 容器半）** | 元素按元素类型过闸 |
| 7 | `ARRAY → PACKED_*` 的**元素位宽** | **本次修（A-2）** | uint8/int32/float 槽收窄曾静默（`44`/`-1294967296`/`inf`/`0`） |
| 8 | `ARRAY/DICTIONARY/INT/FLOAT/BOOL → STRING(含 PackedStringArray 元素)` | **不修** | `Variant::operator String()` 是引擎**已声明**的转换（`stringify`），结果是该值的确定拼写，不是「失败默认值」；拒绝它会无理由收窄 String 属性的可用形态。行为与 TASK-020 前一致（当时 `offsets=["abc"]` 之类是**数值**目标才被拒） |
| 9 | `DICTIONARY → 向量/颜色的分量` | **已修（TASK-020）＋本次补位宽（A-4）** | 分量、以及分量所在成员的宽度都判 |
| 10 | `DICTIONARY → Vector4 分量 / PackedVector4Array 元素` | **本次修（A-3）** | 补上第四张分量表 |
| 11 | 向量对象里的**未知成员**（`{"x":1,"y":2,"zzz":9}`） | **不修** | TASK-020 与迁移源的既有语义：只有目标分量被折叠，多余成员被忽略；不是「转换失败→默认值」，且已线上钉住（`D1_extra_key_ignored...`） |
| 12 | `DICTIONARY → DICTIONARY`、`ARRAY → ARRAY` | **不修（已安全）** | `property_value_from_json` 只保留结构、不做折叠（TASK-020 D-1 的显式保持） |
| 13 | `NIL → OBJECT` | **不修（有意）** | `type_convert(nil, OBJECT)` 是清除资源引用的正式写法（合法语义，非默认值） |
| 14 | `NIL → 其它` | **不修（已安全）** | `can_convert(NIL, X)` 仅对 OBJECT 为 true，其余 TASK-018 闸门已 `-32602` |
| 15 | `FLOAT → INT`（**整值**，如 `1.5 → 1`） | **不修** | 引擎**已声明**的确定性转换（JSON 只有一种数类型，int 属性靠它折叠）；不是「失败→默认」。**但**当 INT 只是中间类型、真实槽位更窄时（packed 元素 / Vector2i 分量），本次已按槽位宽度判（#7/#9） |
| 16 | `FLOAT/INT → COLOR`（`Color::hex`） | **不修** | 每个整数都映射到一个确定的 32 位颜色（低字节为 A），无失败分支 |
| 17 | `property_value_from_json` 的递归（`Variant::NIL` 目标） | **不修（有意）** | 该分支不折叠任何值，故没有分量类型可判（TASK-020 §1 的论证保持） |
| 18 | `serialize_variant` 的 default（**读方向**） | **不修（不在类内）** | 读回值的序列化不是写路径；见 §7 观察 O-1 |

**结论**：在本自查范围内，**不再存在**「值表达不出来 → 引擎写默认值 → 工具报成功」的路径。第 8/11/15/16 条
是有意保留的**已声明确定性转换**（不是失败默认值），已在表中逐条给出理由。

---

## 4. 受影响工具清单

| # | 工具 | 共用转换点 | 本次实测 |
|---|---|---|---|
| 1 | `editor_set_node_property` | `prepare_node_property_value` → `shape_vector_from_json` + `coerce_to_property_type` | **线上实测**：BOOL 8 条坏拼写 + 4 条好拼写 + null/array/dict、Color 2 条、分量位宽 2 条、资源/参照值多条 |
| 2 | `editor_set_node_property_batch` | 同上（写前预校验 + 逐节点写） | **线上实测**：`visible:"abc"`、`modulate:"notacolor"`、TASK-020 的 `position` 分量回归 |
| 3 | `editor_add_nodes_batch` | 同上（含 `shape_vector_from_json`） | **线上实测**：BOOL、`Line2D.points=[{"x":1e300}]`（分量位宽）、`SubViewport.size={"x":3000000000}`（int32 分量），均 `rolled_back` 且无泄漏 |
| 4 | `running_game_set_node_property`（9889） | 同上 | **线上实测**：BOOL、Color、分量回归、可解析字符串正例 |
| 5 | `project_set_setting` | `shape_vector_from_json` + `coerce_to_property_type` | **线上实测**：PackedByteArray/Int32Array/Float32Array/Int64Array/PackedVector4Array/Color 六种目标 |
| 6 | `project_create_resource` | 直接 `coerce_to_property_type(property_value_from_json(...))` | **线上实测**：`Gradient.offsets=[1e300]`、`AudioStreamWAV.data=[300]` → 文件未创建 |
| 7 | `project_edit_resource` | 同上 | **线上实测**：`Gradient.offsets=[1e300]` → `.tres` sha 不变 |
| 8 | `editor_add_resource_to_node_property` | 同上（`editor_write_scene_editor.cpp:662`） | **由共用点推导**（同一行调用；TASK-020 已线上实测该点能拒绝坏值），本任务未单独构造线上用例 |
| 9 | `editor_add_nodes` / `editor_setup_collision_shape` / `editor_setup_navigation_*` 等 setup 族 | `write_node_property` | **由共用点推导**（`editor_node_write.cpp:207/216`、`editor_node_setup.cpp:245/460-462/516-517`） |
| 10 | `project_set_node_property_across_scenes` | `prepare_node_property_value`（逐场景/逐节点，`project_cross_scene_write.cpp:332/431`） | **由共用点推导**（坏值会被记进 `data.scenes.errors` 并整体拒绝） |

> 第 8–10 项明确标注为**推导**，不冒充实测（与 REPORT-020 §4 的记法一致）。

---

## 5. 「同类面已清零」的断言（含自查范围说明）

**断言**：在 §3 的自查范围内（模块全部「JSON 值 → 有类型槽位」的写路径，源类型限于 JSON 可产生的
7 种，目标覆盖标量/字符串/布尔/复合/数组/packed 容器/dictionary/null），**没有任何路径再会把一个无法在目标
中表达的值写成默认值并报成功**。

- TASK-020 报告 §6 列出的三个残留面 **R1（容器元素位宽）/R2（Vector4 元素整形）/R3（STRING→BOOL）全部关闭**；
- 本次读通代码**新发现并关闭**同族第 4 面：**STRING→COLOR**（§1 A-5）；
- 分量位宽（A-4）是 R1 同族的下一层，一并在同一机制里关闭；
- **不在自查范围**（明确排除，理由见 §3）：读/序列化方向（`serialize_variant`）、非 JSON 可达的源类型
  （OBJECT/RID/CALLABLE/SIGNAL/…）、以及表中第 8/11/15/16 条**已声明的确定性转换**。

---

## 6. 五道门（全部在绑定 `de04c86f4c` 的二进制上、串行、未抑制输出）

| 门 | 命令 | 结果 | 退出码 | 证据 |
|---|---|---|---|---|
| ① 契约子集逐字 | `scripts\check_contract_subset.ps1 -Group project_setting_write` | `editor_9888_contract_subset` PASS、`game_9889_contract_subset` PASS、`guard_user_port_9877` PASS；`implemented_union=91 tools (editor) / 53 tools (game)`；`project_set_setting: name=True description=True inputSchema=True` | **0** | `%TEMP%\mcp021-evidence\gate1_contract_subset.txt` |
| ② 三类证据 + 反例矩阵 | `scripts\mcp021_remaining_silent_value_surfaces_evidence.ps1 -Phase post` | **74/74 checks PASS**（同一脚本修前 `-Phase pre`：74 checks / 40 passed / **34 failed**，退出码 1） | **0** | `…\gate2`：`%TEMP%\mcp021-evidence-post\results.json`、`summary.json`、每条 `*.request.json`/`*.response.json` |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **184 cases / 184 passed / 0 failed**；**7509 assertions / 7509 passed / 0 failed**（基线 179/179·7312，只增不减） | **0** | `…\gate3_doctest_modular.txt` |
| ④ 全引擎回归 | `--headless --test` | **1610 cases / 1610 passed / 0 failed / 3 skipped**；**431791 assertions / 431791 passed / 0 failed**（基线 1605/1605·431594） | **0** | `…\gate4_full_test.txt` |
| ⑤ 批收口 | `scripts\accept_m1.ps1` **连跑两次** | 两次均 **22/22 cases passed**；两次 PASS 清单 `Compare-Object` **diff = 0** | **0 / 0** | `…\gate5_accept_run1.txt`、`…\gate5_accept_run2.txt` |

补充机器校验：

```
python docs\scripts\check_tool_groups.py                       -> EXIT=0  TOOL-GROUPS CHECK PASS
python docs\scripts\check_tool_groups.py --check-completeness   -> EXIT=0  TOOL-GROUPS-COMPLETENESS CHECK PASS
```

**端口纪律**：全程只用 9888/9889；9877 的 owner 在每次运行的开工/收尾采样均为用户进程 **PID 36392**
（门①、门⑤、证据脚本的 `guard_user_port_9877` / `port_user_9877_owner_before|after` 均 PASS）；收尾后
9888/9889 均 owner=-1。**未占用、未杀、未重启 9877**。**未执行任何 push**。

**工作树终态**：`git status --short` 仅 4 个**既有**未跟踪项（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、
`install-deps-m0.cmd`）＋本次新增的 1 个脚本（已随 `de04c86f4c` 提交）与本报告。

---

## 7. 观察（未修，供决策层；都不是静默错值）

- **O-1（读方向不对称）**：`serialize_variant` 没有 `VECTOR4/VECTOR4I` 分支，也不展开 packed 数组，因此一个
  `PackedVector4Array` 设置的读回是字符串 `"[(1.0, 2.0, 3.0, 4.0)]"`，而 `Vector2` 读回是对象 `{"x":..,"y":..}`。
  这是**读**的表示不一致，不是写错值；修它会给已验收的读输出换形状，属于契约变更，需决策层裁定。
- **O-2（inf 的连带效应）**：修前 `position={"x":1e300}` 写入 `inf` 后，`editor_get_node_properties` **答不出
  payload**（JSON 序列化 inf 失败）——静默错值不只骗过调用方，还会让读工具失效；这条在 §2.3 有实测。
- **O-3（既有 `FLOAT→INT` 截断）**：整值层面 `1.5` 写进 `int` 属性仍截断为 `1`（引擎已声明转换），与
  packed/分量的「槽位宽度」判定不是同一件事，本次有意未动（§3 #15）。

---

## 8. deviations（与手册/任务书的任何偏离，逐条显式列出）

1. **A-1 对 `"0"` 的语义与引擎 `booleanize` 不同**：本实现把 `"0"` 写成 `false`，而引擎自己的
   `booleanize("0")` 是 `true`（非空串）。这是有意的「拼写优先」判定（任务书允许 `"1"/"0"` 作为可接受拼写并
   要求「不可解析即 `-32602`」），理由见 §1 A-1，已在 doctest 与线上钉住。
2. **A-4 超出任务书 §1.2 的字面范围**：任务书 §1.2 只点名 packed **元素**位宽；本次把同族的**分量**位宽
   （`real_t` 槽、int32 槽）一并关闭，依据是任务书 §1.3「确认每个向量元素的分量都走 D-1 的分量表」与 §1.4
   的「通读并列路径」要求——它是同一缺陷的下一层。
3. **`project_set_setting` 的接受类型表新增 `PackedVector4Array`**：为让 A-3 在线上可构造，并修正该工具拒绝
   消息里「and the Packed*Array family」与实际接受集不一致（唯一缺的成员）。`inputSchema` 未变（`type` 无 enum），
   门① 逐字 PASS。
4. **红阶段 doctest 用的是最终测试修订版之前的一版**（两处**对照**断言字面量写错，见 §2.1 的勘误）；所有
   **缺陷**断言与全部线上证据都是最终修订版产生。
5. **pre 阶段线上证据在脚本改进后用同一 `-Phase pre` 重跑过一次**（给拒绝检查补了显式 `-Type`，使每条检查不依赖
   前一条的 seed；并在「合法数组仍可写」对照前清掉上一个被拒创建的残留）。检查 id 集合未变，报告引用的是
   **最后一次** pre 运行。
6. **未修改**任何契约/映射/组清单文件，也未修改 `docs/DESIGN-DETAIL.md`（该闸门没有 §-级描述可更新）；
   `accept_m1.ps1`、`check_contract_subset.ps1`、`tools_list.renamed.json`、`tool-rename-map.json`、
   `tool-groups*.json` 全部未改动。
7. **未新增规范/决策文档**（PLAYBOOK §5/§7.2）：只写本报告与证据脚本。

**blockers**：无。

---

## 9. 本次改动的文件 sha256（工作树 = `de04c86f4c` 的树）

```
files  -------------------------------------------------------------------
cc938262e927e8d4bce8c7c0c749f813c2dab9d2142fd40c3189c2395b3bcaf2  modules/mcp_server/scripts/mcp021_remaining_silent_value_surfaces_evidence.ps1
483bf72b9be71b605c66ae8fb02c6ed9c8ad5a01152d6af993f83bc9650ec111  modules/mcp_server/tests/test_mcp_server.h
11919402071764540c316db73c63ef85253471a532b834f79102cd00685e88c6  modules/mcp_server/tools/project_setting_write.cpp
5fadb30eb3a1eb3e207b2ee7c711a5c6776ea4dfd128420ce6e0613eb963e6c2  modules/mcp_server/tools/running_game_node_write.cpp
a56f2e5e69df036080be234b7cc393d9f696141c21d464faa2eda5ecf60dac3e  modules/mcp_server/tools/running_game_node_write.h
d7789f34bfb1180aa26a61264246afe7ce3e9fcc51fb9bbca687854c4ba4c8ed  modules/mcp_server/tools/tool_helpers.cpp
f4d7c06e9fb94ba6288da26b267087d684511a676632baf05ad9e0288f277b19  modules/mcp_server/tools/tool_helpers.h
8d89a02bab8ea0a5f2bd92db616d3bde3502cfc46375b7ad57fdfc5b49a006d2  modules/mcp_server/scripts/accept_m1.ps1            （未改动）
3a66b9cd08576b1cd3ec4b20fbba4c418367779b556142852e53b47491f467c8  modules/mcp_server/scripts/check_contract_subset.ps1（未改动）
binary -------------------------------------------------------------------
CAA3C690E4454FF28B6453D1BD80934B09B9F571CFCD32D6252045E40664EB0C  bin/godot.windows.editor.x86_64.console.exe（--version = 4.8.dev.custom_build.de04c86f4）
```

### 9.1 新增/改动的测试（`tests/test_mcp_server.h` 的 `namespace Task021`，+449 行）

| 用例 | 钉住什么 |
|---|---|
| `[MCPServer] TASK-021 A-1: a string reaches a bool property only when it spells a boolean` | 14 个坏拼写 → `-32602`；4+2 个可接受拼写且**写入拼写所指的值**（`"false"`→false、`"0"`→false）；原生 bool/int 不变 |
| `[MCPServer] TASK-021 A-2: a packed container's element has to fit the element width` | Byte 的 `300`/`-1`/`256`、Int32 的 `3e9`/`±`越界、Float32 的 `1e300`/`1e-300` → `-32602` 且点名 `value[0]`；区间端点与可解析字符串仍可写；Int64/Float64/String 数组无新增判定 |
| `[MCPServer] TASK-021 A-3: a Vector4 element goes through the same component table` | `Vector4` 坏分量/缺分量/合法值；`PackedVector4Array` 对象元素的整形与打包；无整形步骤的 `coerce` 路径响亮拒绝 |
| `[MCPServer] TASK-021 A-4: a component has to fit the width of the slot it fills` | 单精度构建下 `Vector2/Vector3/Color` 分量 `1e300` → `-32602` 点名 `value.x/z/b`；`Vector2i/Vector3i` 的 int32 越界与端点；区间内仍可写 |
| `[MCPServer] TASK-021 A-5: a string reaches a colour property only when the engine can read it` | 8 个读不出的颜色串 → `-32602`；`#rgb`/`#rgba`/`#rrggbb`/命名色/三位十六进制正例；`INT→COLOR` 不变；`PackedColorArray` 元素同闸 |

---

## 10. next_step_recommendation

1. **派全新验收子代理独立复核**：用 `build_local.cmd`（`tests=yes`）重建并校验 `--version` == HEAD，然后重跑
   门①–⑤；重点用**反例**独立构造 §2.5 的九类值 × 五条面，并用「错误码 + 文件 sha256 相同 + 另一读工具读回旧值」
   三条判据判定（**不要**只用「读回值 vs 请求值」比较）。
2. **决策层裁定 §7 的三条观察**：O-1（Vector4/packed 的读回表示与 Vector2 不对称）与 O-3（整值 `FLOAT→INT`
   截断）是否值得下一轮任务；O-2 已随本任务修掉根因（不再写入 inf）。
3. **规范补强建议**：把「已声明的确定性转换（stringify 到 String、整值 FLOAT→INT）不属于『失败→默认』类」
   与「槽位宽度（uint8/int32/float/real_t）必须与转换关系分开判」写进 DESIGN-DETAIL 的写值闸门小节，避免下一轮
   再把它们当成新缺陷重复报告。
4. **流程建议**：doctest 的 `REQUIRE` 在本 harness 下**不会中断用例**（失败后继续执行），测试里对
   `REQUIRE` 之后的索引访问必须自带 size 守卫——本次红阶段第一次运行因 `values[0]` 越界触发 SEH 崩溃，已修正，
   建议写进 PLAYBOOK §7。
