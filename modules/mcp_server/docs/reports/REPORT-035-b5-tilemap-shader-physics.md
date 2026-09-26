# REPORT-035 — B5 批次 3（tilemap / shader / physics）验收报告

- **任务书**：`modules/mcp_server/docs/tasks/TASK-035-b5-tilemap-shader-physics.md`
- **批次**：B5 第 3 批（7 组 / 15 个工具 + §0 契约覆盖）
- **代码锚点**：`1e8b4075ee`（实现）+ `de96b61b18`（**仅测试**：新增第 4 个 narrowing 点的 doctest，`git show --stat de96b61b18` = 1 file）
- **批次前 HEAD**：`e6b50d9884`（TASK-035 任务书）
- **构建**：`modules\mcp_server\scripts\build_local.cmd -Force`（tests=yes），`--version` = `4.8.dev.custom_build.de96b61b1` == `HEAD`（`de96b61b18`）
- **结论**：**通过**。门 ① 7 组 × 3/3、门 ② 67/67、门 ③ 251 用例 / 13978 断言 0 失败、门 ④ 1677 用例 / 438260 断言 0 失败、门 ⑤ `accept_m1.ps1` ×2 均 22/22、门 ⑥ 三段全绿。
- 门 ①/②/⑤ 与回归在 `1e8b4075ee` 上执行；`de96b61b18` 只改了测试文件，门 ③/④ 在新锚点上重跑（两棵树的**产品代码逐字节相同**，可用 `git show --stat de96b61b18` 核对）。

---

## 1. 交付清单

### 1.1 15 个工具（契约逐字、工具名来自 `docs/tools_list.renamed.json`）

| 组 | 工具 | 说明 |
| --- | --- | --- |
| editor_tilemap_write | `editor_set_tilemap_cell` | **fix_implementation_first**，见 §3 |
| editor_tilemap_write | `editor_set_tilemap_cells_in_rect` | **fix_implementation_first**，全成全退，见 §3 |
| editor_tilemap_write | `editor_remove_all_tilemap_cells` | 回答真实删除数量，见 §3 |
| editor_tilemap_read | `editor_get_tilemap_cell` | 写—读互证，含 `layer` 的整数缺省规范化 |
| editor_tilemap_read | `editor_get_tilemap_info` | TileSet / source / 已用格数概览 |
| editor_tilemap_read | `editor_get_tilemap_used_cells` | `get_used_cells()`，排序后输出（HashMap 顺序不确定） |
| editor_shader_write | `editor_set_shader_material` | 真替换：槽位解析 + 读回，见 §4 |
| editor_shader_write | `editor_set_shader_param` | **E-5**：`ShaderMaterial::set_shader_parameter`，见 §4 |
| project_shader_write | `project_create_shader` | 原子写盘 + `.gdshader` 守卫 + 重扫描 |
| project_shader_write | `project_edit_shader` | 文件必须已存在（-32001），模式指令校验 |
| project_shader_read | `project_read_shader` | 内容 / 行数 / 声明模式 |
| project_shader_read | `project_get_shader_params` | 引擎自己的 uniform 列表 |
| editor_physics_write | `editor_set_physics_layers` | 节点物理层掩码，见 §5 |
| editor_physics_read | `editor_get_collision_info` | 子树遍历，shape 的 `{type,path}` 形状 |
| editor_physics_read | `editor_get_physics_layers` | 掩码 + 位 + 项目层名 |

### 1.2 新增 / 修改文件

- 新增实现：`tools/tilemap_shared.{h,cpp}`、`editor_tilemap_write.{h,cpp}`、`editor_tilemap_read.{h,cpp}`、`shader_shared.{h,cpp}`、`editor_shader_write.{h,cpp}`、`project_shader_write.{h,cpp}`、`project_shader_read.{h,cpp}`、`physics_shared.{h,cpp}`、`editor_physics_write.{h,cpp}`、`editor_physics_read.{h,cpp}`
- 修改：`tools/registration.cpp`（7 个 include + 7 个注册调用）、`tools/editor_scene_3d_write.{h,cpp}`（§0）、`tools/tool_helpers.{h,cpp}`（`publish_text_atomically`）、`tools/tool_builder.{h,cpp}`（`integral_value` 导出）、`tests/test_mcp_server.h`
- 契约 / 清单：`docs/tools_list.renamed.json`、`docs/tool-groups-b5.json`、`scripts/gen_renamed_contract.py`
- 门 ② 证据脚本：`scripts/mcp035_b5_tilemap_shader_physics_evidence.ps1`（纯 ASCII）

### 1.3 每个工具的一行「引擎参考（API + file:line）」

| 工具 | 引擎参考 |
| --- | --- |
| `editor_set_tilemap_cell` | `TileMapLayer::set_cell(coords, source_id, atlas_coords, alternative_tile)` — `modules/tilemap/tile_map_layer.cpp:2768`（单参数重载的擦除形态是 `TileMapLayer::erase_cell`，`:2813`） |
| `editor_set_tilemap_cells_in_rect` | 同上逐格写入 + `TileMapLayer::get_used_cells()` — `tile_map_layer.cpp:2887`（快照 / 校验 / 回滚） |
| `editor_remove_all_tilemap_cells` | `TileMapLayer::clear()` — `tile_map_layer.cpp:2832` |
| `editor_get_tilemap_cell` | `get_cell_source_id` — `:2840`、`get_cell_atlas_coords` — `:2851`、`get_cell_alternative_tile` |
| `editor_get_tilemap_info` | `TileMapLayer::get_tile_set()` + `TileSet::has_source(int)` — `modules/tilemap/tile_set.h:433` |
| `editor_get_tilemap_used_cells` | `TileMapLayer::get_used_cells()` — `tile_map_layer.cpp:2887` |
| `editor_set_shader_material` | `MeshInstance3D::set_surface_override_material(surface, mat)` — `scene/3d/mesh_instance_3d.cpp:375`、`ShaderMaterial::set_shader()` — `scene/resources/material.cpp:388` |
| `editor_set_shader_param` | `ShaderMaterial::set_shader_parameter(name, value)` — `scene/resources/material.cpp:420`、`Shader::get_shader_uniform_list()` — `scene/resources/shader.cpp:150` |
| `project_create_shader` | 文本原子写（`DirAccess`/`FileAccess`）+ `EditorFileSystem` 重扫描；模式取自 `Shader::MODE_SPATIAL/CANVAS_ITEM/SKY/FOG/PARTICLES` |
| `project_edit_shader` | 同上的原子写 + `Shader::set_code()` 编译校验 — `scene/resources/shader.cpp:83` |
| `project_read_shader` | `FileAccess` 读取 + `Shader::set_code()` 校验声明模式 |
| `project_get_shader_params` | `ResourceLoader::load()` + `Shader::get_shader_uniform_list(List<PropertyInfo>*)` — `shader.cpp:150` |
| `editor_set_physics_layers` | `CollisionObject2D::set_collision_layer(uint32_t)` — `scene/2d/physics/collision_object_2d.cpp:144`、`set_collision_mask` — `:157` |
| `editor_get_collision_info` | `CollisionShape2D::get_shape()` + `CollisionObject2D::get_shape_owners()` / `shape_owner_get_shape()` |
| `editor_get_physics_layers` | `get_collision_layer()` — `collision_object_2d.cpp:153`、`get_collision_mask()` — `:166`、项目层名 `ProjectSettings` 的 `layer_names/{2d,3d}_physics/layer_N`（引擎注册点 `scene/register_scene_types.cpp:1320` / `:1324`） |

---

## 2. §0：`editor_set_material_3d.material_slot` 由 string 改为 integer

### 2.1 契约差异（唯一改动点）

`scripts/gen_renamed_contract.py` 新增一条 `SCHEMA_OVERRIDES["set_material_3d"]`，`mode=replace`：

- `material_slot` 声明为 `integer`，描述 `表面索引（整数）；省略 = 第一个表面（索引 0）`；
- 覆盖原因逐字引用被替换成员与 `["node_path","material_path"]`，未增删任何 required 成员；
- 生成器版本 `1.10.0`，覆盖条目 **17 → 18**；
- 生成结果 `docs/tools_list.renamed.json`：171 个工具，sha256 `c844ec8af9ef00d2e6ec7008c9806b3e2b16757e78794d3ccca0704edf844256`，自检 OK。

实现侧 `tools/editor_scene_3d_write.{h,cpp}`：`set_material_3d_on(Node*, node_path, material_path, int p_slot, err)`；入参经 `slot_from_variant`（接受 `INT`、整值 `FLOAT`、以及**十进制字符串**）后写入 `surface_material_override/<n>`；回答里的 `material_slot` 是整数。

### 2.2 「索引被声明成字符串」全量普查

对 171 条契约条目逐条扫描所有 string 类型参数（共 255 个），判定「是否在表达一个序数 / 索引」：

- **真缺陷 1 条**：`editor_set_material_3d.material_slot`（本次修复）。
- 其余 254 个 string 参数全部是名称 / 路径 / 代码 / 枚举名 / 口令等，不属于「索引」。
- 留待后续批次评估的候选（**不是**本批缺陷）：
  1. `editor_set_shader_material.material_slot`：它是**槽位名**（`material` / `material_override` / `material_overlay` / `surface_material_override/<n>`），实现同时接受十进制索引；语义上不是纯序数，保留 string 更贴合引擎（`Material` 槽位在引擎里就是属性名）。
  2. `editor_simulate_key.keycode`：引擎枚举名（`Key.KEY_A`），属于「枚举被声明成字符串」，与「索引」不同类。

### 2.3 活证据（门 ② 子节 B）

- `tools/list` 的 9888 上 `editor_set_material_3d.inputSchema.properties.material_slot.type == "integer"`（`s0_live_schema_material_slot_integer`）；HEAD 契约里同一条是 `string`，重生成后是 `integer`（`s0_head_material_slot_is_string` / `s0_now_material_slot_is_integer`）。
- 用 `editor_execute_gdscript` 造一个 **2 个表面**的 `ArrayMesh`，`material_slot = 1`（整数）写入后，`editor_get_node_properties` 读 `surface_material_override/1` 有材质、`/0` 为空（`s0_integer_slot_is_accepted` / `s0_slot_one_holds_the_material`）。
- 旧的十进制字符串 `"0"` 仍然可用（`s0_legacy_string_slot_still_works`），老客户端不破。

---

## 3. 两个 `fix_implementation_first` 工具（红 → 修 → 绿 全程）

### 3.1 红阶段（迁移行为，实测）

在基线二进制上先写会失败的最小用例，`%TEMP%\t035_red.log`：**7 个用例 / 53 条断言失败**，其中：

- `editor_set_tilemap_cell`：迁移源调的是单参数 `TileMapLayer::set_cell(coords)`，那是**擦除**形态（`source_id` 缺省 = `TileSet::INVALID_SOURCE`），所以它一边把格子擦掉、一边回答 `set: true`（假成功 + 数据破坏）。红用例断言「写入的 `source_id` / `atlas_coords` 能被读回」失败。
- `editor_set_tilemap_cells_in_rect`：迁移源**丢掉**调用者给的 `source_id` / `atlas_coords`，逐格用缺省值写，矩形里的内容不是调用者要的东西。
- `editor_remove_all_tilemap_cells`：迁移源回答常量计数（实测 `removed: 0`），删除数量不可信。

红阶段还当场暴露了三个环境/契约事实（随后一并修掉）：注册计数 31→35 的旧断言、`editor_get_tilemap_cell.layer` 缺整数缺省规范化、以及 E-5 的测量路径。

### 3.2 修复后的行为（`tools/editor_tilemap_write.cpp` + `tilemap_shared.cpp`）

1. **先解析再写**：`tilemap_resolve_cell_target()` 用图层自己的 `TileSet` 校验 `source_id` 与 `atlas_coords`（`has_source` / `has_tile`），未知 source / 该 source 没有该 atlas → `-32602` 且**不写**（消息里列出可用 source id）。
2. **写用四参数重载**，随后**读回比对**；不一致 → `-32000` 内部错误而不是谎报成功。
3. **矩形写全成全退**：先预校验全部格子（上限 65536），再快照 `get_used_cells()`，写入后逐格校验，任一不符则**整块恢复**并回答 `restored: true`。
4. **清除工具**回答 `removed` / `remaining` / `cell_count_before`（`TileMapLayer::clear()` 前后计数），并校验后置条件。
5. 回答里带 `empty`、`set`、`applied`、`changed`、`previous`，删除/擦除与写入可由调用者区分。
6. `get_used_cells()` 走引擎内部 `HashMap`，输出按 y 再 x 排序以保证确定性。

### 3.3 绿阶段活证据（门 ② 子节 C，真实 `TileMapLayer` + 真实 `TileSet` 源）

- 写 `(3,4)` source 0 atlas (0,0) → `editor_get_tilemap_cell` 读回 source 0 / atlas (0,0) / `empty: false`（`ff_set_cell_reports_the_stored_cell`、`ff_write_then_read_matches`）。
- `source_id = 999` → `-32602`；atlas `(1,0)`（该 source 没有此图块）→ `-32602`；两次拒绝之后原格子**分毫未动**（`ff_bad_source_refused`、`ff_bad_atlas_refused`、`ff_refusals_left_the_cell_untouched`）。
- 2×2 矩形 → `filled: 4` / `verified: 4` / `restored: false`，`used_cells.count == 5`（`ff_rect_fills_and_verifies`、`ff_used_cells_counts_five`）。
- 矩形里放一个非法元素 → 整次调用 `-32602` 且仍为 5 格（`ff_rect_is_all_or_nothing`）。
- `editor_remove_all_tilemap_cells` → `removed: 5` / `remaining: 0`，随后 `editor_get_tilemap_info` 的 `cell_count == 0`（`ff_clear_reports_the_real_count`、`ff_info_confirms_empty`）。

---

## 4. E-5：shader 参数写入路径（实测结论）

任务书的假设是「迁移源的复合路径 `node.set("material:shader_parameter/<name>", v)` 静默失败，改用 `ShaderMaterial::set_shader_parameter`」。实测把这句话拆成三个可核对的事实：

1. **迁移源的写法确实是静默 no-op**（doctest `TASK-035 E-5` 断言）：`Object::set(StringName("material:shader_parameter/x"))` 没有 `:` 拆分（`scene/main/node.cpp`→`Object::set` 直接落到 `_setv`），值写不进去，而调用者拿到的是「成功」。
2. **但引擎路由本身存在**：`Object::set_indexed()` **会**拆分属性路径并在 `ShaderMaterial::_set`（`scene/resources/material.cpp:198-232`，需要材质持有**已编译** shader）里接受 `shader_parameter/<name>`；本模块自己的 `editor_set_node_property`（TASK-028）正是这么走的。门 ② 用真实 9888 端点验证：`material_override:shader_parameter/albedo` 通过 `editor_set_node_property` **确实写进去了**，随后 `editor_execute_gdscript` 读回 `{x:1,y:0,z:0}`（`e5_composite_path_reaches_the_engine_through_set_indexed`）。
3. **结论（修正后的因果）**：迁移源的缺陷是它那次**单个 `Object::set("a:b")`** 的写法（报告成功、什么都没发生，属于「第三类：假成功」），不是引擎缺能力。因此本批的落点仍是更稳的杠杆——`ShaderMaterial::set_shader_parameter`：不需要路径猜测、不依赖材质的 remap 缓存，且能用 `Shader::get_shader_uniform_list` 校验名字。

交付的行为：

- `editor_set_shader_param`：先解析材质（无 ShaderMaterial → `-32001` 并给出「先调 `editor_set_shader_material`」的建议；材质没有 shader → `-32000` 状态错误），再用引擎的 uniform 列表校验名字（不在列表 → `-32001`），值走模块统一的 `property_value_from_json → shape_vector_from_json → coerce_to_property_type` 三步（float uniform 用 `ValueSlot::FLOAT32`），写入后读回，回答带 `write_path: "ShaderMaterial::set_shader_parameter"`、`uniform_type`、`previous_value`、`new_value`、`applied`、`changed`。
- 活证据：`e5_engine_api_write_is_reported`、`e5_engine_reads_the_value_back`（引擎自己 `get_shader_parameter` 读回）、`e5_tool_write_overrides_the_property_path`、`e5_second_write_confirms_the_first`（第二次写入的 `previous_value` = 第一次的值）、`e5_unknown_parameter_refused`。
- `editor_set_shader_material`：解析调用者点名的槽位（`material` / `material_override` / `material_overlay` / `surface_material_override/<n>`），复用已有 `ShaderMaterial` 或新建后 `set_shader()`，读回并回答 `reused_existing` / `previous_material` / `material_slots`；`uniform_count` 来自引擎的 uniform 列表（活证据 `e5_material_assigned_to_the_named_slot`，doctest 覆盖「不同槽位写不同材质」与「未知槽位被拒并列出可用槽位」）。

---

## 5. 物理层写入 / 读取

- `editor_set_physics_layers`：`layer_type` 是闭集 `collision` | `mask`（迁移源的 fall-through 默认会把任何笔误都写成 `collision_layer` 并把笔误原样回显 —— 现在 `-32602` 并列出两个合法值）。
- `layers` 是引擎的 `uint32_t`；`ValueSlot` 只有 WIDE/REAL_T/FLOAT32/INT32/UINT8，没有 32 位无符号，因此在**碰节点之前**显式判定 `0..4294967295`（`-32602`），避免 `4294967296` 被引擎自己的拷贝截断成 0。
- 写入后读回比对，不一致 → `-32000`；回答带 `layers` / `previous_layers` / `new_value` / `applied` / `changed` / `layer_bits` / `layer_names`。
- `editor_get_physics_layers` / `editor_get_collision_info` 回答同一份节点记录，`collision_shapes` 里的形状是模块统一的 `{type, path}` 对象形状（GDR-25 §23.5），`owner_body` 是子树根下的相对路径。
- 活证据（门 ② 子节 F）：写 mask 5 → 读回 5 / bits `[1,3]` / `dimension: "2d"`；`editor_get_collision_info` 报出 `BodyShape`（`type: CollisionShape2D`、`owner_body: "Body"`）；`layers = 4294967296` → `-32602` 且 mask 仍是 5。
- **环境事实（实测）**：doctest 进程里 `Main::test_setup()` 在服务器初始化**之前**跑，`memnew(CharacterBody2D)` 会直接让测试进程崩（用「逐行 flush 到文件」的探针定位到崩溃发生在第一个探针之前，即 `memnew` 处）。因此 doctest 只固定「不需要物理服务器」的那一半（常量、`layer_type` 闭集、width 判定、非碰撞节点的拒绝、plain 节点子树遍历），**整节点那一半只在 9888 活证据里证**。

---

## 6. 门证据

### 6.1 门 ② 当场测出的两个缺陷（doctest 漏掉、活线抓到）

1. **嵌套整数在线上是 double**。`ConvertTo-Json` 发出的 `atlas_coords = {"x":0,"y":0}` 经 JSON 解析后是 `Variant::FLOAT`，而我最初的 `nested_int` 只接受 `INT`，于是：
   `{"error":{"code":-32602,"message":"Member 'atlas_coords.x' must be an integer, got float"}}`、
   `"Member 'rect.x' must be an integer, got float"`。
   顶层参数没暴露这个问题，因为 `require_int` 走的是模块**唯一**的整数规则 `_integral_value`（它明确允许 `2.0` 这种 JSON 写法，TASK-010 §3.3）。修法不是复制一份判断，而是把这条规则**导出**为 `MCPTools::integral_value`（`tools/tool_builder.h`，`tool_builder.cpp` 里仍只有一处定义），`nested_int` 改用它。doctest 增补：`{x:0.0,y:0.0}` 必须通过、`{x:0.5,y:0.0}` 必须 `-32602`。
2. **vec3 uniform 的 JSON 形状被拒**。`editor_set_shader_param` 直接把 `{x,y,z}` 交给 `coerce_to_property_type`，得到
   `Parameter 'value' cannot be written to a Vector3 property: ... (Variant::can_convert) does not list Dictionary -> Vector3`。
   模块其他所有写路径都是三步走（`property_value_from_json → shape_vector_from_json → coerce_to_property_type`，即 `prepare_node_property_value`）。修法：在 coerce 之前插入 `shape_vector_from_json`。doctest 增补：`{x,y,z}` 写入并读回、缺一个分量 `-32602` 且不写。

两条都属于「文档/设计没写、活线才暴露」的缺陷，已在本报告与代码注释里留下位置（`editor_tilemap_write.cpp` 的 `nested_int`、`editor_shader_write.cpp` 的取值三步）。

### 6.2 门 ② 三段证据 + 跨工具零字符串手术链

`scripts/mcp035_b5_tilemap_shader_physics_evidence.ps1`（真实 9888 / 9889）：

- 三段证据：15 个工具逐个「成功 / 缺参 -32602 / 底层失败 -32001或-32000」；`editor_get_collision_info` 无 required 成员 → 用**未声明参数**当 -32602 见证；`project_create_shader` 没有「可指向的缺失引用」→ 该行显式声明 `n/a`，不静默跳过。
- 跨工具链（两条，全部以**解析后的对象**传递标识符，脚本自计数 `StringOps == 0`）：
  1. 6 步 shader 链：`project_create_shader → project_edit_shader → project_get_shader_params → editor_set_shader_material → editor_set_shader_param → project_read_shader`（路径、uniform 名、槽位名都是上一步答案里的对象）。
  2. 5 步 tilemap 链：`editor_set_tilemap_cell → editor_get_tilemap_cell → editor_set_tilemap_cells_in_rect → editor_get_tilemap_used_cells → editor_remove_all_tilemap_cells`（`source_id` 与 `atlas_coords` 对象直接回喂）。
  3. 物理 3 步链：`editor_set_physics_layers → editor_get_physics_layers → editor_get_collision_info`（每组一条活链的要求）。
- 结果：**67/67 checks passed**（summary sha256 `9d8e33b70d816768e8d0fe2116ce809736a361aa0046b550e7d3914c3a239614`）；每个请求/响应体都在 `%TEMP%\task035-b5-batch3\evidence\*.json`，`curl.exe -s -o <file>` + 盘上字节的 sha256。
- 端口纪律：9877 的用户编辑器（PID）前后 pid 相同；9888/9889 用完自动释放；`editor_*` 在 9889 上被 `-32601` 拒（`scope_9889_has_no_editor_tool`、`scope_9889_editor_tool_is_32601`），4 个 project 工具在 9889 可用（`scope_9889_serves_the_project_tools`）。

### 6.3 其余门

| 门 | 命令 | 结果 |
| --- | --- | --- |
| ① 契约逐字 | `check_contract_subset.ps1 -Group <g>` × 7 组（tilemap write/read、shader write、project shader write/read、physics write/read） | 每组 **3/3 checks passed**（9888 + 9889），日志 `%TEMP%\t035_gate1_<group>.log` |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **251 用例 / 13978 断言 / 0 失败** |
| ④ 全量 doctest | `--headless --test` | **1677 用例 / 438260 断言 / 0 失败**（3 skipped，与批次前一致） |
| ⑤ M1 验收 | `scripts\accept_m1.ps1` ×2 | 两次均 **22/22 cases passed**（implemented 135 / editor、57 / game；contract 171） |
| ⑥ narrowing 三段 | `python scripts\check_narrowing_points.py` | **38 points / 38 pinned**，PASS |
| ⑥ | `python scripts\check_narrowing_points.py --coverage` | exit 0，声明拼写 17 条，边界（未覆盖拼写）逐条列出 |
| ⑥ | `scripts\mcp031_gate6_coverage_probes.ps1` | **101/101 checks passed**（log sha256 `67cd6340555c37d1020417d85d30e16c5a69e0b8b92a5fa909d8ae65371b9747`） |

回归（`1e8b4075ee` 上重跑既有证据脚本）：

| 脚本 | 结果 |
| --- | --- |
| `mcp030_live_open_scene_write_evidence.ps1` | 22 checks / 0 failed |
| `mcp032_d3_d4_d6_evidence.ps1` | 39 checks / 0 failed |
| `mcp033_b5_animation_evidence.ps1` | 75/75 |
| `mcp034_b5_audio_particle_theme_evidence.ps1` | **109/114**，5 条失败全部是**脚本自己的「before」侧**（见下） |

`mcp034` 的 5 条失败（`s0_head_has_no_animation_member_on_add_state` / `..._blend_tree` / `s0_head_has_no_xfade_time` / `..._priority` / `..._advance_condition`）不是行为回归：TASK-034 的证据脚本把「before」定义成 `git show HEAD:docs/tools_list.renamed.json`，而它自己在 `fc724ce49a` 上跑的时候 HEAD 还没有那 4 个成员。锚点前移后 HEAD 已包含它们。已核对：`git show fc724ce49a:…` 中 `advance_condition` / `xfade_time` 出现 **0** 次，`git show e6b50d9884:…`（= `1e8b4075ee^`）已包含 `advance_condition`。其余 109 条（含全部活线与「after」侧）通过。

### 6.4 B5 批次进度

`python docs\scripts\check_tool_groups.py --batch B5` → **PASS**：`implemented=true` 组 **18** 个、工具 **44** 个（批前 11 组 / 29 个）。

---

## 7. 新 narrowing 点 × 门 × 证据（GDR-24 §22.3b 规则 4）

扫描器结论：本批**没有新增**「声明拼写」类的 narrowing 点（38 points / 38 pinned 与批前一致）。但本批新增代码里确实有 4 处对值的收窄路径，逐条列出它们各自过的门与证据：

| # | 位置 | 收窄内容 | 门 | 证据 |
| --- | --- | --- | --- | --- |
| 1 | `tools/editor_physics_write.cpp`（`set_physics_layers_on`） | `int64 → uint32_t`：`0..4294967295` 显式判定（`ValueSlot` 无 32 位无符号） | GDR-22 §20.1 手工判定 | doctest：`-1` 与 `4294967296` → `-32602`（消息含 `0..4294967295`）；门 ② `PH_04_wide_mask_refused` / `PH_05_mask_unchanged`（拒绝且 mask 仍为 5） |
| 2 | `tools/editor_tilemap_write.cpp`（`int32_argument`） | `int64 → int`：坐标 / `source_id` / `alternative_tile` 走 `ValueSlot::INT32` | GDR-22 `value_fits_slot` | doctest：`x = 3000000000` → `-32602 "32-bit tile coordinate"`；门 ② `FF_03` / `FF_04`（非法 source / atlas 被拒且不写） |
| 3 | `tools/editor_tilemap_write.cpp`（`nested_int`） | 嵌套对象成员同样走 `int32_argument` | GDR-22 + §6.1 的整数规则统一 | doctest：`{x:0.5}` → `-32602`；`{x:0.0}` 通过（`integral_value`）；门 ② 全部 tilemap 写调用 |
| 4 | `tools/editor_shader_write.cpp`（`set_shader_param_on`） | `double → float`：float uniform 用 `ValueSlot::FLOAT32`（shader 的 `float` 与构建精度无关，GDR-24 §22.2） | GDR-22 `value_fits_slot(FLOAT32)` | doctest（`de96b61b18`）：`uniform float` 写 `1e300` → `-32602`（消息含 `does not fit in`）、写 `0.5` 通过并读回 |

`tools/tilemap_shared.cpp` 中的 `(int)` 转换都在上述 INT32 门**之后**，属于「已判定值的复制」，不构成新的收窄点（扫描器把它们归为 `safe`，与既有 38 条一致）。

---

## 8. 契约与清单差异

- `docs/tools_list.renamed.json`：171 条；sha256 `c844ec8af9ef00d2e6ec7008c9806b3e2b16757e78794d3ccca0704edf844256`；覆盖 18 条（新增 `set_material_3d`）。
- `docs/tool-groups-b5.json`：12013 字节，sha256 `1720b266d0304fec80c53e7139026a142957a9b43232056ab1b519e826b89476`；`git diff e6b50d9884..1e8b4075ee` 对该文件恰好 **7 行 `implemented: false → true`**，没有任何其它改动（本批没有第二个 schema 成员改动）。

---

## 9. 偏离 / 文档缺陷 / 风险

1. **文档缺陷**：`docs/tool-groups-b5.json` 中 `editor_set_physics_layers` 的 note 说的是「通过 ProjectSettings 写项目碰撞层**名字**」，与该工具的 schema（`node_path` + `layers`）和 rename-map 的理由（`改编辑场景节点的物理层掩码`）不一致。实现按 schema + rename map（节点作用域）落地，读侧另提供项目层名。记在此处，不改本批范围外的任务书 / 清单。
2. **回归脚本锚点相对性**：TASK-034 证据脚本的「before」是 `HEAD`，锚点前移必然使 5 条失效（§6.3 已核对）。
3. **doctest 覆盖边界（环境事实）**：(a) `memnew(CharacterBody2D)` 在 `Main::test_setup()` 阶段会让进程崩 → 物理整节点路径只在 9888 证；(b) doctest 不允许写 `res://`（它映射引擎仓库根）→ `project_create_shader` / `project_edit_shader` 的成功路径只在活线证。两处都在代码注释与本报告写明，不用「看起来通过」替代。
4. **未做的两件本批范围外的事**：`editor_set_shader_material.material_slot` 仍是 string（槽位名，接受十进制索引），`editor_simulate_key.keycode` 仍是枚举名——两者在 §2.2 记录为后续批次候选。
5. **未 push**：按纪律只做本地提交（`1e8b4075ee`、`de96b61b18`），未推远端。
6. **仓库根有未跟踪文件**（`build-m0.cmd`、`install-deps-m0.cmd`、`graphify-out/`、`.graphifyignore`），本批未触碰、未提交。

## 10. 与任务书的差异

- 任务书要求「≥1 条跨 ≥4 工具的零字符串手术链」，实际交付 **2 条**（6 步 / 5 步）+ 1 条 3 步物理链，且「零字符串手术」由脚本自己的计数器（0）作为机器事实，而非文字声明。
- E-5 的落点（改用 `set_shader_parameter`）按任务书执行；但对原因的结论被实测**修正**为「迁移源那次单个 `Object::set("a:b")` 的写法是静默 no-op，引擎的 `set_indexed` 路由其实是通的」，见 §4。
- 门 ② 额外测出并修掉了两个 doctest 漏掉的缺陷（§6.1），这是任务书未预见的收益。

---

## 11. 复现命令

```text
# 构建（cmd，串行，不静默）
cd F:\RustProjects\godot-mcp-pro\code\godot
modules\mcp_server\scripts\build_local.cmd -Force
bin\godot.windows.editor.x86_64.console.exe --version        # 4.8.dev.custom_build.de96b61b1

# 门 ③ / ④
bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="[MCPServer]*"
bin\godot.windows.editor.x86_64.console.exe --headless --test

# 门 ①（7 组，各自起 9888/9889）
cd modules\mcp_server\scripts
python ..\docs\scripts\check_tool_groups.py --batch B5
powershell -NoProfile -ExecutionPolicy Bypass -File check_contract_subset.ps1 -Group editor_tilemap_write
#   ... editor_tilemap_read / editor_shader_write / project_shader_write /
#       project_shader_read / editor_physics_write / editor_physics_read

# 门 ②
powershell -NoProfile -ExecutionPolicy Bypass -File mcp035_b5_tilemap_shader_physics_evidence.ps1

# 门 ⑤
powershell -NoProfile -ExecutionPolicy Bypass -File accept_m1.ps1      # ×2

# 门 ⑥
python check_narrowing_points.py
python check_narrowing_points.py --coverage
powershell -NoProfile -ExecutionPolicy Bypass -File mcp031_gate6_coverage_probes.ps1
```
