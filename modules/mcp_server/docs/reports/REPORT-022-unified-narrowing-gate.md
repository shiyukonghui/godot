# REPORT-022 — 统一「槽位宽」收窄闸门（D-4）+ 资源写后回读（D-5）+ 跨进程测试报告（D-6）

- 任务书：`docs/tasks/TASK-022-unified-narrowing-gate.md`（按 `docs/tasks/PLAYBOOK-group-port.md` 执行）
- 依据：`docs/reports/REPORT-AUDIT-M4b.md`（M4 第二次独立验收，判 `fail`，D-4 high / D-5 medium / D-6 medium）
- 执行者：TASK-022 实现者（本报告所有数字与输出均由本次自行运行产生）
- 仓库：`F:\RustProjects\godot-mcp-pro\code\godot`，分支 `feature/mcp-server-module`
- 日期：2026-09-22
- **被验二进制**：`bin\godot.windows.editor.x86_64.console.exe`
  - `--version` = `4.8.dev.custom_build.861c1cde1`；`git rev-parse --short HEAD` = `861c1cde1a`（**前缀一致**：
    引擎自报 9 位，git `--short` 给 10 位，逐字符前缀比较通过）
  - SHA256 = `bb82ecc06370df3a728d624ed44160b8610378829dcaa21c23ea4598da83f8cb`
  - 构建：`modules\mcp_server\scripts\build_local.cmd -Force`（`tests=yes`），**未抑制 scons 输出**，`EXIT_CODE=0`
- 端口纪律：9877 全程属于用户 **PID 36392**（`Godot_v4.7.1-stable_mono_win64`），本次仅用 9888 / 9889；**未 push**
- **门与 HEAD 的绑定关系**：全部门与线上证据都跑在 `--version = 4.8.dev.custom_build.861c1cde1`、HEAD `861c1cde1a`
  的那一刻（证据：`G0_version_matches_head`）——即本任务的源码**进入提交之前**。三个提交（`55c24e5ca7` /
  `b6c51d883c` / 本报告）之后 HEAD 前移，但 `tools/**` / `tests/**` 的字节自那次构建起**未再改动**
  （其后只加了证据脚本与本报告两处非编译文件）。`bin/` 不受版本控制，下一位验收者按 PLAYBOOK §3
  的规定**重新构建并重新校验**即可。
- 工作树终态：`git status --porcelain` 仅 4 个**既有**未跟踪项（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`）+ 本任务新增的 1 个证据脚本
- 本任务**不新增工具**（113/171 不变），**未改契约 / 映射 / 生成器**

---

## 0. status / commits

- `status`：**完成**（D-4 / D-5 / D-6 三项全部落地；四道门 + §3 证据门全绿；`blockers` 为空）

| sha | 一行说明 |
|---|---|
| `55c24e5ca7` | TASK-022：统一收窄闸门（D-4）+ 资源写后回读（D-5）+ 跨进程报告（D-6）+ `build_local.cmd -Force` + DESIGN-DETAIL GDR-22 |
| `b6c51d883c` | TASK-022 tests：D-4/D-5/D-6 的红/绿 doctest（6 个新 `[MCPServer]` 用例） |
| `（本报告的提交）` | `docs(mcp_server): REPORT-022 …`（sha 见 `git log`：它随本文件的每次修订而变） |
工作树内改动文件（全部在 `modules/mcp_server/**`）：

| 文件 | 改动 |
|---|---|
| `tools/tool_helpers.h` | 新增 `ValueSlot` / `value_fits_slot` / `scalar_member_slot`；`coerce_to_property_type` 增加槽参数；新增报告桥接 API |
| `tools/tool_helpers.cpp` | 收窄闸门唯一实现；元素闸门改为调用它；`coerce_to_property_type` 拆成「类型转换 + 槽位判定」；报告持久化 / 读回；`build_test_report_from` |
| `tools/running_game_node_write.cpp` | `_component_fits_slot` 的内部实现**删除**，改为调用同一条闸门（分量表只声明槽宽） |
| `tools/project_setting_write.cpp` | 显式传 `ValueSlot::WIDE`（`ProjectSettings` 存 Variant） |
| `tools/project_write_resource_scene.cpp` | D-5：`project_create_resource` 写后回读（`changed` / `properties_set` / `ignored`） |
| `tools/editor_testing_read.cpp` | D-6：`editor_get_test_report` 读 `user://` 桥接文件（诚实空 + 来源 + `clear` 语义） |
| `scripts/build_local.cmd` | 新增 `-Force`（删陈旧 test 对象）；注释写明「不加 `-Force` 可能跑旧用例产生**假绿**」 |
| `docs/DESIGN-DETAIL.md` | 新增 **GDR-22**（§20，七小节）+ §15 索引一行 |
| `tests/test_mcp_server.h` | 6 个新用例（3 个红+3 个绿）；TASK-019 的报告用例增加桥接文件清理（见 §7 偏离 9） |
| `scripts/mcp022_unified_narrowing_gate_evidence.ps1` | 本次新增：§6 的线上证据 |

---

## 1. 逐工具表（无新增工具；下表是**行为被本任务改动的 3 个工具**）

| new_name | 迁移源位置 | 可观察契约（改动后） | C++ 落点 | 与迁移源的差异 |
|---|---|---|---|---|
| `editor_set_node_property` | `commands/node.rs`（`set_property`） | 同前，**新增**：目标成员为单精度 `real_t` 时，不存活槽位的值 → `-32602`（消息含参数名 + 引擎实写值 + 范围）；不写入 | `tools/running_game_node_write.cpp`（`write_node_property` / `prepare_node_property_value`）→ `tools/tool_helpers.cpp`（`coerce_to_property_type` + `value_fits_slot`） | 迁移源无此判定（属「工具真的能用」口径，PLAYBOOK §6.6） |
| `editor_set_node_property_batch` | `commands/batch.rs:147` | 同前；坏值在**任何节点写入之前**整体拒绝（`before any node was written`） | 同上（`set_node_property_batch_on` 逐节点预校验） | 同上一行 |
| `editor_add_nodes_batch` | `commands/batch.rs:270` | 同前；新节点属性在**挂载前**校验，拒绝时 `root` 子节点数不变 | 同上（`add_nodes_batch_on`） | 同上一行 |
| `running_game_set_node_property` | `addons/godot_mcp_rs/mcp_runtime_agent.gd:159` | 同前；同上槽位宽判定 | 同上（`running_game_node_write.cpp`） | 同上一行 |
| `project_set_node_property_across_scenes` | `commands/batch.rs:257` | 同前（`dry_run` 默认 true、`force`）；坏值 → 事务整体拒绝 `-32000`，`data.scenes.errors[].reason` 携带**同一条** `-32602` 语义，`Nothing was written` | `tools/project_cross_scene_write.cpp`（复用 `prepare_node_property_value`） | 同上一行；**且不再能把 `rotation = inf` 写进 `.tscn`** |
| `project_create_resource` | `commands/resource.rs`（`create_resource`） | `{"path","type","properties_set","ignored","changed"}`：`changed:{<prop>:{old,new}}` 为**真回读**；`properties_set` 只含「回读值 = 请求值」的属性；被 setter 夹取 / 忽略的列入 `ignored`（含 `requested`/`stored`/`reason`） | `tools/project_write_resource_scene.cpp` | 迁移源不回读（M4b D-5） |
| `project_edit_resource` | `commands/resource.rs`（`set_resource_property`） | **未改**（本就是真回读），作为 D-5 的同口径参照 | 同上 | 一致 |
| `editor_get_test_report` | `commands/test.rs:561`（`get_test_report`） | 同契约（无新参数）；输出增加 `report_path` / `report_file_present` / `report_unavailable_reason` / `cleared`，读到游戏报告时另加 `report_written_at_unix` / `report_source_process` / `report_format_version`；`source` ∈ {`game_process_file`,`editor_process`} | `tools/editor_testing_read.cpp` + `tools/tool_helpers.cpp`（桥接） | 迁移源的 `message` 假报告仍不复刻（TASK-019 口径）；迁移源的 `user://` 文件 IPC **恢复为真** |

其余 105 个已实现工具**零改动**（`tools/list` 逐字不变，见 §5 门①）。

---

## 2. 核心：统一收窄闸门（D-4）的覆盖清单与调用点

### 2.1 唯一判定

```
MCPTools::value_fits_slot(value, ValueSlot, 参数名, 槽位描述, error)   // tools/tool_helpers.cpp
MCPTools::ValueSlot { WIDE, REAL_T, INT32, UINT8 }                     // tools/tool_helpers.h
MCPTools::scalar_member_slot(Variant::Type) -> ValueSlot               // FLOAT -> REAL_T，其余 WIDE
```

| `ValueSlot` | 槽 | 判据（本构建单精度） | 拒绝消息给出的注释 |
|---|---|---|---|
| `WIDE` | `double` 成员 / `int64_t` 成员 / `PackedFloat64Array`·`PackedInt64Array` 元素 / `ProjectSettings` 值 / String | 恒通过 | — |
| `REAL_T` | `real_t`：标量成员、向量·颜色分量、`PackedFloat32Array` 元素 | `\|x\| > FLT_MAX`（→`inf`）或 `x != 0 && (float)x == 0`（→`0`） | `inf` / `0` |
| `INT32` | `int32_t` | 越界 | 低 32 位（`3000000000 → -1294967296`） |
| `UINT8` | `uint8_t` | 越界 | 低 8 位（`300 → 44`，`-1 → 255`） |

`REAL_T` 在 `REAL_T_IS_DOUBLE` 构建下恒通过（`#ifdef` 分支）。

### 2.2 调用点清单（**任何写入之前**）

| # | 调用点 | 传入槽 | 说明 |
|---|---|---|---|
| 1 | `coerce_to_property_type(...)` 默认 `FROM_TARGET_TYPE` | `scalar_member_slot(target)` | **所有属性成员写路径**自动获得；`FLOAT` 目标 → `REAL_T` |
| 2 | `_element_fits_container()`（`tool_helpers.cpp`） | `_container_element_slot()`：`BYTE→UINT8`、`INT32→INT32`、`FLOAT32→REAL_T`、其余 `WIDE` | 数组元素的类型转换递归走内部 `_coerce_to_property_type_typed`，**不**套成员规则（`PackedFloat64Array` 元素是 `double`） |
| 3 | `running_game_node_write.cpp` 的 `_check_components()` | 分量表给出的 `REAL_T` / `INT32` | 函数体已删除，改为调用闸门 |
| 4 | `project_setting_write.cpp` | `WIDE`（显式） | `ProjectSettings` 以 Variant 存储，非有类型成员 |

**由 1 覆盖的 5 条写路径**（TASK-022 §1 的清单，全部先于 `Object::set()`）：

1. `editor_set_node_property` → `write_node_property` → `prepare_node_property_value` → `coerce_to_property_type`
2. `editor_set_node_property_batch` → `set_node_property_batch_on`（逐节点 `prepare_node_property_value` **预校验**，全成功或全回滚）
3. `editor_add_nodes_batch` → `add_nodes_batch_on`（挂载前 `prepare_node_property_value`）
4. `running_game_set_node_property`（9889）→ `write_node_property`
5. `project_set_node_property_across_scenes` → `prepare_node_property_value`（事务 phase 1 预校验）

**另有 3 条资源属性写路径同样由 1 覆盖**：`project_create_resource`、`project_edit_resource`、
`editor_add_resource_to_node_property`（都是 C++ 资源成员，`FLOAT` → `REAL_T` 正确）。
`editor_setup_*` / `editor_add_*` 族经 `write_node_property` 亦在内。

### 2.3 「为什么这一处能覆盖全部写入路径」

模块里**每一个**把 JSON 值交给 `Object::set()` 的入口，其最后一步都是
`coerce_to_property_type(...)`；TASK-022 把槽位判定放进这个函数的**出口**（类型转换成功之后），
因此不可能存在「转换过了但槽位没判」的路径。唯一的形状差异（成员 / 元素 / 分量 / Variant 存储）
只用 `p_slot` 一个参数表达，判定本体仍然只有一份实现——这正是把
「容器元素 → 分量 → 标量」三次补丁合并成一条规则所要求的结构。

### 2.4 同类面清零的范围声明（**必须逐条读**）

**声明已闭合（有本次线上证据）**：

- `double → float32` **溢出**（`1e300`/`3.5e38`/`-3.5e38`/`"1e300"` → `inf`）；
- `double → float32` **非零下溢**（`1e-300`/`1e-46` → `0`）；
- `int64 → uint8`（`PackedByteArray` 元素：`300`/`-1`/`256`）；
- `int64 → int32`（`PackedInt32Array` 元素、`Vector2i`/`Vector3i` 分量）；
- `float32` 容器元素（`PackedFloat32Array`）；
- 向量 / 颜色分量（`Vector2`/`Vector3`/`Vector4`/`Color`）；
- packed 向量数组元素（`PackedVector2Array`/`Vector3Array`/`Vector4Array`）；
- **标量属性成员**（本次新增：5 条写路径 + 3 条资源写路径）；
- 并保留既有环节：`can_convert`、字符串可解析性 / 有限性、布尔 / 颜色拼写。

**显式声明不覆盖（诚实边界，非遗漏，已写进 GDR-22 §20.3）**：

- **标量 `INT` 成员的 C++ 宽度**：`PropertyInfo` 只带 Variant 类型、不带 C++ 宽度，
  无法区分 `int` 成员与 `int64_t` 成员；一律按 32 位判会**误拒**合法 64 位成员。
  该处保持 `WIDE`，由「写入后读回真值」保证诚实（M4b 观测的 `z_index = 3000000000`
  引擎丢弃越界值、响应回显写后真值 `5`，**不属静默错值**）。宽度可知的两处（元素、分量）已覆盖。

**显式声明**不属该类（PLAYBOOK §7.7「已声明的确定性转换」，本任务未改其行为）：
整值 `FLOAT→INT` 截断（`1.9→1`、`[255.9]→[255]`）、`INT→FLOAT`、`INT→BOOL`（`booleanize`，非零即真）、
`BOOL→FLOAT`、写入 `String` 目标时的字符串化、对象中不属于目标分量的键被忽略、
`"0"→false` 与引擎 `booleanize("0")==true` 的**有意背离**（TASK-021 已声明）。

---

## 3. 红 / 绿证据（真实输出）

### 3.1 红阶段（**实现之前**，`-Force` 重建后的同一 HEAD 二进制）

写测试 → `build_local.cmd -Force`（`EXIT_CODE=0`）→
`--headless --test --test-case="*TASK-022*"`：

```
[doctest] test cases:   3 |  0 passed |  3 failed | 1613 skipped
[doctest] assertions: 103 | 32 passed | 71 failed |
[doctest] Status: FAILURE!
```

关键失败行（原文，节选）：

```
test_mcp_server.h(12571): ERROR: CHECK_FALSE( MCPTools::coerce_to_property_type(refused[i], Variant::FLOAT, out, error, "value") ) is NOT correct!
  values: CHECK_FALSE( true )
test_mcp_server.h(12599): ERROR: CHECK_FALSE( MCPTools::prepare_node_property_value(node, "rotation", bad[i], converted, error) ) is NOT correct!
test_mcp_server.h(12601): ERROR: CHECK( Math::is_finite((double)node->get_rotation()) ) is NOT correct!
test_mcp_server.h(12602): ERROR: CHECK( node->get_rotation() == (real_t)0.5 ) is NOT correct!
test_mcp_server.h(12671): ERROR: CHECK_FALSE( set.has("min_value") ) is NOT correct!
test_mcp_server.h(12673): ERROR: CHECK( changed.has("min_value") ) is NOT correct!
test_mcp_server.h(12675): ERROR: CHECK( ignored.has("min_value") ) is NOT correct!
test_mcp_server.h(12762): ERROR: CHECK( (int)report.get("total", 0) == 2 ) is NOT correct!
  values: CHECK( 0 == 2 )
test_mcp_server.h(12793): ERROR: CHECK( (bool)report.get("report_file_present", true) == false ) is NOT correct!
```

> `12601` 是**在进程内直接量到的缺陷**：`prepare_node_property_value(node,"rotation",1e300,…)` 返回「成功」，
> 而 `Node2D` 的 `rotation` 真的变成了非有限值。这是 D-4 的最小复现，不依赖任何线上装置。
> 红阶段全文：`%TEMP%\task022_red.txt`。

### 3.2 绿阶段（实现之后）

```
[doctest] test cases:   6 |   6 passed | 0 failed | 1613 skipped
[doctest] assertions: 195 | 195 passed | 0 failed |
[doctest] Status: SUCCESS!
```

6 个用例：`D-4 标量 real_t`、`D-5 资源回读`、`D-6 跨进程报告`（红→绿）；
`统一闸门 ValueSlot`、`批量路径写前拒绝`、`报告桥接往返与诚实空`（实现后补的闸门级用例）。
全文：`%TEMP%\task022_green.txt`。门③ 全文：`%TEMP%\task022_gate3.txt`。

### 3.3 基线对比（只增不减）

| 门 | 本任务前（REPORT-AUDIT-M4b §7） | 本次 | 差 |
|---|---|---|---|
| 模块 doctest | 184 cases / 184 passed；7509 assertions | **190 / 190；7716 / 7716** | +6 cases，+207 assertions |
| 全引擎 `--test` | 1610 / 1610 / 0 failed / 3 skipped；431791 assertions | **1616 / 1616 / 0 failed / 3 skipped；431998 / 431998** | +6 cases，+207 assertions |

`0 failed`，passed 的增加**恰好等于**新增用例数（没有旧用例被改绿或改红）。

---

## 4. 5 条写路径 × 反例矩阵（**四条证据形态**）

线上装置：`scripts/mcp022_unified_narrowing_gate_evidence.ps1`（9888 编辑器 / 9889 游戏，scratch `%TEMP%\mcp022-scratch-t2`），
结果集 `%TEMP%\mcp022-results-t2.json`，**89 条 check，0 失败**。

四条证据形态（本次的实际判据，见 §7 偏离 2）：

1. **错误码**（矩阵中给出的 `code`）；
2. **响应回显值有限**：拒绝响应**没有** `result` 载荷、`error.data` 中**没有** `new_value`/`old_value`/`stored`
   （旧的缺陷形状是 `code=0` + `new_value=1e99999`，恰好被这条排除）；正向对照要求 `new_value` 是有限数；
   同时记录拒绝消息**点名**了引擎实写值（溢出 `inf` / 下溢 `0`）——那是诊断文本，不是回显；
3. **落盘文件不得含 `inf`/`nan`**：显式 `editor_save_scene` 后对 `.tscn` **字节**扫描（正则 `(?i)(?<![a-z])(inf|nan)(?![a-z0-9])` + `1e99999`），并给出保存前后 sha256；
4. **另一个读工具**读到旧值未变：`editor_get_node_properties`（模块自身序列化）+ `editor_execute_gdscript`
   的 `str(Actor.rotation)`（**独立求值通道**，M4b 证明只有它能看见 `inf`）双读；跨场景路径另用
   `load("res://xscenes/good.tscn")` 直接读**文件内容**。

### 4.1 路径 1：`editor_set_node_property`（编辑器 9888，`Actor.rotation`，旧值 `0.5`）

| 反例 | ① 错误码 | ② 回显 | ③ 文件 sha256 前后 | ④ 双读旧值 |
|---|---|---|---|---|
| `1e300` | **-32602** | 无 `result`、无值回显；消息点名 `inf` | `26482974…1395` → 同 | props `0.5` / gd `0.5` |
| `3.5e38` | **-32602** | 同上 | 同 | 同上 |
| `-3.5e38` | **-32602** | 同上 | 同 | 同上 |
| `"1e300"`（字符串） | **-32602** | 同上（解析后仍在闸门处被拒） | 同 | 同上 |
| `1e-300` | **-32602** | 同上；消息点名 `0` | 同 | 同上 |
| `1e-46` | **-32602** | 同上 | 同 | 同上 |
| `1e30`（**对照**） | `0` | `new_value` 有限（`1e+30`） | 文件正常写入、无 `inf`/`nan` | gd = 写入值 |
| `1e-30`（**对照**） | `0` | `new_value` 有限 | 同上 | gd = 写入值 |

原文（节选）：

```
[PASS] P1_1e300_code :: code=-32602 new_value_echo= message=Parameter 'value' is the number 1e+300, which does not fit in the 32-bit float slot this value is copied into (this build's single-precision real_t: a scalar member, a vector/colour component, or a PackedFloat32Array element): the engine's own copy would write inf instead of the value you sent. The largest 32-bit float is about 3.4e38.
[PASS] P1_1e300_no_value_echo :: no result payload / no value echo in error.data; message names the engine's value: inf (named in the refusal message)
[PASS] P1_1e300_file_clean :: scenes/main.tscn sha256 26482974c1a653b4ad65e8296d9dc2432f3aaa7163e766c5d02ef0ad9db01395 -> 26482974c1a653b4ad65e8296d9dc2432f3aaa7163e766c5d02ef0ad9db01395; no inf/nan in bytes
[PASS] P1_1e300_read_old :: editor_get_node_properties rotation=0.5 ; editor_execute_gdscript str(rotation)=0.5
[PASS] P1_1e-300_code :: code=-32602 …the engine's own copy would write 0 instead of the value you sent…
```

### 4.2 路径 2/3/4/5

| 路径 | 反例 | 结果 |
|---|---|---|
| 2 `editor_set_node_property_batch`（`node_type=Node2D`） | `1e300`、`1e-300` | **-32602** + 无值回显 + sha 不变 + `Actor.rotation` 双读 `0.5`；消息以 `before any node was written` 收口 |
| 3 `editor_add_nodes_batch` | `1e300`、`"1e300"` | **-32602** + 无值回显 + sha 不变 + **场景树内不存在 `D4Node`**（未挂载任何节点）+ `Actor.rotation` 双读 `0.5`；消息以 `nodes[0]:` 前缀定位 |
| 4 `running_game_set_node_property`（9889） | `1e300`、`1e-46` | **-32602** + 无值回显 + `running_game_get_node_properties` 与 `running_game_execute_gdscript` 双读 `0.5`（另先给出一条 `seed rotation=0.5 code=0` 的正向对照） |
| 5 `project_set_node_property_across_scenes`（`dry_run=false,force=true`，**真的会写盘**） | `1e300`、`"1e300"` | 外层 **-32000**（工具的全成功/全回滚信封），`data.scenes.errors[0].reason` **就是同一条 -32602 语义**；无值回显；`xscenes/good.tscn` sha256 `a45e61fd…a780` **不变**且字节内无 `inf`/`nan`；`load("res://xscenes/good.tscn")` 读到 `X1|X2 rotation = 0.5|0.5` |

原文（节选）：

```
[PASS] P3_1e300_nothing_attached :: scene tree contains D4Node = False ; sha before save=26482974…1395
[PASS] P4_1e-46_code :: code=-32602 message=Parameter 'value' is the number 1e-46, which is too small for the 32-bit float slot…
[PASS] P4_1e-46_read_old :: running_game_get_node_properties rotation=0.5 ; running_game_execute_gdscript str(rotation)=0.5
[PASS] P5_1e300_code :: outer code=-32000 inner reason=Parameter 'value' is the number 1e+300, which does not fit in the 32-bit float slot…
[PASS] P5_1e300_file_clean :: xscenes/good.tscn sha256 a45e61fd659d0f440b91cd62079575a0b8c8e5509106c4cb96d1f115e87fa780 -> 同 ; no inf/nan in bytes
[PASS] P5_1e300_read_old :: load(res://xscenes/good.tscn) X1|X2 rotation = 0.5|0.5
```

> **M4b 的原始缺陷形状**（`Applied: every closed scene was saved…` + 文件内 `rotation = inf`）在本次**不可复现**：
> 同一调用现在是上面那条拒绝。这正是 D-4 的判据从「读回值 ≠ 请求值」升级为「文件字节里没有 `inf`」的原因。

---

## 5. D-5 回读形状前后对照

`project_create_resource`，`type=Curve`：

| 输入 | 修改前（M4b 实测） | 本次实测 |
|---|---|---|
| `min_value=5.0` | `{"changed":{},"properties_set":["min_value"]}`，文件内 `_limits=[0.99,…]`（**谎报**） | `properties_set=[]`；`changed.min_value={"new":0.990000009536743,"old":0.0}`；`ignored.min_value={"requested":5.0,"stored":0.990000009536743,"reason":"…it clamps or refuses input outside its own range…"}` |
| `min_value=1e300` | 同样 `properties_set:["min_value"]`，实际仍 0.99 | **`-32602`**（D-4 闸门在创建文件**之前**拒绝；`file exists=False`）——D-5 的第二个反例由 D-4 的修复一并关闭 |
| `min_value=0.25,max_value=0.75`（**真生效的正例**） | `properties_set` 两项 | `properties_set=["min_value","max_value"]`；`changed={min_value:{old:0.0,new:0.25}, max_value:{old:1.0,new:0.75}}`；`ignored={}`；文件 sha256 `141691d0…6998` |
| `min_value=0.1`（单精度往返，**不**应被当成 ignored） | — | `properties_set` 含 `min_value`（`FLOAT` 目标按 `real_t` 宽度比较，`(float)0.1 == (float)stored`） |
| `project_edit_resource({min_value:0.5})`（同口径参照） | `changed:{min_value:{old,new}}` | `changed={min_value:{old:0.25,new:0.5}}`（**同形状**） |

「报成功必须以回读为据」现在有了可核对的字段：**`changed` 是回读**，`properties_set` 是「回读=请求」的子集，
`ignored` 是「引擎没按请求存」的显式清单。

---

## 6. D-6 跨进程报告：真实数字与诚实失败

线上（`9889` 游戏进程 → `9888` 编辑器读取）：

```
[PASS] D6_game_assertions_ran :: pass=true fail=false fail.reason=expected rotation eq 123, found 0.5
[PASS] D6_bridge_file_written :: user://mcp_test_report.json exists=True sha256=5b4cbdb1455122fc116489be0be4ab1a66df5d99d66f922cc798d866efd30acf bytes=512
[PASS] D6_editor_sees_game_report :: total=2 passed=1 failed=1 source=game_process_file report_path=user://mcp_test_report.json written_at_unix=1790091398
[PASS] D6_clear_is_cross_process :: first total=2 cleared=["editor_process","game_process_file"] file left=False second total=0 no_results=True report_file_present=False
```

- **两个断言在游戏进程内运行**（一个过、一个失败）→ 游戏侧 `record_test_result` **原子写**
  `user://mcp_test_report.json`（`publish_file_atomically`：临时兄弟文件 + rename）→ 编辑器端点
  `editor_get_test_report` 读到 **`total=2, passed=1, failed=1`**，每条 `details` 明细齐全（失败条目带 `reason`），
  并给出 `source=game_process_file`、`report_path`、`report_written_at_unix=1790091398`。
- **诚实失败（文件不存在/为空）**：返回 `total=0`、`no_results=true`、`pass_rate="N/A"`、
  `report_file_present=false` + `report_unavailable_reason`（"…does not exist" / "…holds no recorded results" /
  "…is not valid JSON: …"）。**不伪造 `total`**。doctest 另覆盖「文件存在但 `results` 为空」与
  「缺 `results` 键」两条路径。
- **accumulator 语义写清**（工具注释 + DESIGN-DETAIL GDR-22 §20.7 + 报告）：
  **每进程一份内存列表 + 一个 `user://` 文件把游戏进程的列表带给编辑器进程**；它不是跨进程内存直读，也不可能变成。
  `clear`（默认 true）清空**编辑器进程累加器 + 桥接文件**，答案用 `cleared` 列表说明真的清了哪一侧；
  游戏进程**内存**不可达、工具**不声称**清了它（游戏下次记录会重新持久化自己的整份列表）。

---

## 7. 门（真实输出与退出码）

| 门 | 命令 | 结果 | 退出码 |
|---|---|---|---|
| ⓪ 构建绑定 | `modules\mcp_server\scripts\build_local.cmd -Force`（`tests=yes`）→ `--version` | `EXIT_CODE=0`；`4.8.dev.custom_build.861c1cde1` == HEAD `861c1cde1a` 前缀 | 0 |
| ① 契约子集逐字 | `check_contract_subset.ps1 -Group editor_testing_read` | editor 9888 = **91**、game 9889 = **53**、contract 171；两条本组工具三字段逐字 True；`editor_*` 在游戏端点**正确缺席**；`guard_user_port_9877` pid_before=36392 pid_after=36392 | **0**（3/3 PASS） |
| ② 三类证据 + 证据形态 | 见 §8 | 见 §8 | — |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **190 cases / 190 passed / 0 failed**（1429 skipped）；**7716 assertions / 7716 passed / 0 failed**；`Status: SUCCESS!` | **0** |
| ④ 全引擎回归 | `--headless --test` | **1616 / 1616 / 0 failed / 3 skipped**；**431998 / 431998 / 0 failed**；`Status: SUCCESS!` | **0** |
| ⑤ 批收口 | `accept_m1.ps1` **连跑两次** | 两次 **22/22 cases passed**；两次 PASS 清单 `Compare-Object` **diff = 0**（22 行）；两次均打印 `implemented tools = 91 (editor endpoint) / 53 (game endpoint); contract = 171` | **0 / 0** |
| 补充 | `check_tool_groups.py --check-completeness` / `--batch B4` | 两项均 `CHECK PASS`（105 = 40+7+58，两两不相交；B4 的 7 个各一次） | **0 / 0** |

门输出文件：`%TEMP%\mcp022_gate3.txt`、`task022_gate4.txt`、`task022_gate1.txt`、`task022_accept1.txt`、`task022_accept2.txt`、`mcp_server_build_local.log`。

---

## 8. ② 三类证据（成功 / 缺参 / 底层失败）与不可构造类

本次线上证据（`mcp022_unified_narrowing_gate_evidence.ps1`，89 checks / 0 failed）覆盖：

- **成功**：`Actor.rotation` 写 `1e30` / `1e-30` / `"1.5"` 全部 `code=0` 且 `new_value` 有限；
  `project_create_resource` 的 `min_value/max_value` 正例；`project_edit_resource` 正例。
- **缺参 / 类型错**：由门①的门禁契约与既有 doctest 维持（本任务未改参数面）；
  本脚本的 `P4_*_seed_ok`、`D6_game_assertions_ran` 给出两端的活调用证据。
- **底层失败**：**不可构造须显式声明**——D-4 的反例**全部**是可构造的（见 §4），
  失败类里唯一由本任务新引入的是「值不存活槽位」这一类，它本身是 `-32602` 而非底层失败；
  路径 5 的「场景不可加载」失败面在 TASK-018 的证据里已覆盖，本任务未重复。
- **跨工具端到端活证据链**（比单工具更容易抓缺陷）：
  `running_game_assert_node_state`（过/失败两次）→ 游戏侧 `user://` 落盘 → `editor_get_test_report`（读回
  `total=2/failed=1` + 明细）→ `clear` → 再读为诚实空。这条链**跨两个进程、一个文件、两个端点**。

---

## 9. 脚本与文件 sha256

| 文件 | sha256 |
|---|---|
| `bin\godot.windows.editor.x86_64.console.exe`（被验二进制） | `bb82ecc06370df3a728d624ed44160b8610378829dcaa21c23ea4598da83f8cb` |
| `scripts/build_local.cmd` | `d41479d68037121db479ae392366231a918f93ddbc672bbc3f2efeb80ae5837b` |
| `scripts/mcp022_unified_narrowing_gate_evidence.ps1` | `3156feda1f699f072a77ff64fdec59e1354bf7ec55ef7e9383ac1ebc7688c688` |
| `docs/DESIGN-DETAIL.md` | `d918ed2e784f8326b8be281dfd1f1707a3b62c004c647e0b2a6bd695c2a12acc` |
| `tests/test_mcp_server.h` | `cd013d1fde7ddf086923ef3eaebdb95e750d8fe852978f0a53ac46d80ad5284f` |
| `tools/tool_helpers.h` | `3949510378a59ae6df54cc620b59e822e7f7980b23fd59f89b6b67c803dfc8ce` |
| `tools/tool_helpers.cpp` | `fb43af0ec3f7aca4f35bbda0fa3896d07d62554982e3179fac818d1c271ca80b` |

**未改动**：`docs/tools_list.renamed.json`、`docs/tool-rename-map.json`、`docs/tool-groups*.json`、
`docs/scripts/**`（契约 / 映射 / 生成器 / 清单一处未动）。

---

## 10. deviations（逐条显式）

1. **路径 5 的外层错误码是 `-32000`（不是 `-32602`）**：`project_set_node_property_across_scenes` 的契约是
   「全成功或全回滚」的事务信封；值级拒绝被放进 `data.scenes.errors[].reason`，**语义就是那条 `-32602`**。
   任务书 §2 要求「错误码 `-32602`」在 5 条路径上一致；本路径按工具自身契约收口，四条证据形态仍全部成立。
   已在 §4.2 与本条显式声明。
2. **证据形态 ② 的解释收窄为「无 `result` 载荷 / `error.data` 无值回显」**：
   任务书要求「响应回显值必须有限（不得出现 `inf`/`nan`/`null` 来掩盖）」，同时要求「消息须给出引擎会写的值」；
   溢出场景下后者**就是** `inf`。因此把 ② 判在**回显字段**上（拒绝响应不得有 `new_value` 等），
   并把「消息点名 `inf`/`0`」作为**诊断证据**记录。旧缺陷形状（`code=0` + `new_value=1e99999`）被本判据排除。
3. **`properties_set` 语义收紧**：从「被赋过值的属性」改为「回读值就是请求值的属性」，并新增 `ignored`。
   这是任务书 §3 允许的两种修法之一（「不被列为已设置，或明确标注 ignored」），本次两者都做。
   既有 doctest（`resource_name`、`bake_resolution=200.0`）不受影响，全绿。
4. **D-5 的第二个反例（`min_value=1e300`）由 D-4 关闭**，不再是 D-5 的独立意愿：闸门在文件创建**之前**拒绝，
   因此「报成功但没写」在该输入上已不可达。报告与 GDR-22 §20.6 都写明这一交叉。
5. **D-6 的 `clear` 会删除桥接文件**：这是为了让既有契约「`clear` 后下一次调用从零开始」在**跨进程**意义上也成立
   （TASK-019 的用例正是钉这一条）。游戏进程**内存**不可达、未被声称已清；答案用 `cleared` 列表说明真实范围。
6. **不判标量 `INT` 成员宽度**（诚实边界）：见 §2.4 与 GDR-22 §20.3。
7. **`project_set_setting` 显式传 `WIDE`**：`ProjectSettings` 以 Variant 存储，按成员规则判会误拒可存储的大浮点数。
8. **新增模块内公共 API**：`ValueSlot` / `value_fits_slot` / `scalar_member_slot` /
   `build_test_report_from` / `test_report_bridge_path` / `persist_test_report_to` / `load_persisted_test_report_from`
   （均在 `tools/tool_helpers.{h,cpp}`，属模块内部共享面，不涉及对外契约）。
9. **改了 1 个既有 doctest**：TASK-019 的 `editor_get_test_report reports the assertions that really ran`
   在开头增加 `DirAccess::remove_absolute(test_report_bridge_path())`。理由：D-6 之后「没有结果」=
   「本进程累加器为空**且**没有持久化报告」，用例必须自备干净状态，否则会依赖上一次运行留下的文件
   （非 hermetic）。断言语义未变。
10. **`--version` 自报 9 位 hash**，`git rev-parse --short HEAD` 给 10 位；按前缀比较通过。
11. **`tool_groups` / 契约 / 映射 / 生成器未改**；本任务不新增工具（113/171 不变）。
12. **TASK-021 的两处形状判定函数体被删除**（`_element_fits_container` 的 switch、
    `_component_fits_slot` 的 float/int 分支），改为调用统一闸门——这是任务书 §1「不再逐类打补丁」的直接要求，
    不是行为变更；两者各自的 doctest（TASK-021 A-2 / A-4）全绿。

---

## 11. blockers

**无**。构建、双端点、四道门、证据装置全部一次或重试内通过。

环境观察（记入决策日志线索，未阻塞）：

- `--import` 第 1 次退出码非 0、第 2 次成功（`S0_import_ok :: --import exit 0 on attempt 2`）。
  脚本按 TASK-021 的约定重试最多 3 次。这与 M4b `unconfirmed` 第 5 条（`--import` 偶发非 0）**同类**，
  本次仍**未能复现**其 `0xC0000005` 具体形态，故只记录「attempt=2 成功」，不作断言。

---

## 12. risks / next_step_recommendation

1. **标量 `INT` 成员宽度仍是唯一未判的收窄面**（诚实边界）。若后续要求覆盖，需要引擎侧提供
   「成员 C++ 宽度」的信息（`PropertyInfo` 目前没有），或按类维护一张已验证的宽度表——不要靠猜。
2. **`clear` 删除桥接文件**：多客户端并发（同一游戏进程 + 多个编辑器客户端）下，一次 `clear`
   会让其他客户端的一次读取落空。语义已写明；若将来要求「只清本进程」，需要契约层面的显式参数。
3. **D-5 的 `ignored` 判据是「回读 ≠ 请求」**：对**故意归一化**的 setter（例如把 `Vector2` 分量四舍五入）
   会把它标成 `ignored` 而不是「已按语义设置」。目前未观测到此类资源属性；
   建议下一轮抽样若干资源类型的 setter（`Environment`、`CameraAttributes`）确认。
4. **`Vector4i` / `Rect2` / `Transform2D` 等复合属性的分量宽度**仍属 M4b §11 的 `unconfirmed` 面
   （本 fork 里这些类型的 JSON 对象形态多以 `can_convert(DICTIONARY, X)=false` 响亮拒绝，
   不进入分量表）——**未见静默错值**，但未在线构造实例。建议下一轮作为补充验收项。
5. **窗式（非 headless）下的截图/视口能力**仍无法在自动化门里覆盖（M4b risk 6），与本任务无关，继续挂账。
6. **回归护栏**：下一轮任何改动 `tools/tool_helpers.*` 的任务，必须重跑：
   `--test-case="*TASK-021*"`、`*TASK-022*`、`[MCPServer]*`，以及本报告 §4 的 5×N 矩阵（脚本一条命令可复现）。

---

## 13. 复现方式

```powershell
cd F:\RustProjects\godot-mcp-pro\code\godot
cmd /c "modules\mcp_server\scripts\build_local.cmd -Force"          # tests=yes，删陈旧 test 对象
.\bin\godot.windows.editor.x86_64.console.exe --version             # == git rev-parse --short HEAD 前缀
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp022_unified_narrowing_gate_evidence.ps1 -Tag t2
.\bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="[MCPServer]*"
.\bin\godot.windows.editor.x86_64.console.exe --headless --test
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\check_contract_subset.ps1 -Group editor_testing_read
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\accept_m1.ps1   # 连跑两次
```

期望：89/89、190/190、1616/1616、3/3、22/22 ×2；`%TEMP%\mcp022-results-t2.json` 内 `failed=0`。