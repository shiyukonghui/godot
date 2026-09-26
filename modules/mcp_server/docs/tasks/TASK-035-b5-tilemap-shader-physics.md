# TASK-035 — B5 批次 3：tilemap(6) / shader(6) / physics(3) 共 15 工具（**含 2 个 fix-first + E-5**）+ `material_slot` 改整数

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册），再读本文件。
> 引擎优先（§21/GDR-23）、顺手性（§23/GDR-25）、门⑥（§22.3/§22.3b）是本批的规范依据。
> 报告写到 `docs/reports/REPORT-035-b5-tilemap-shader-physics.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. §0 收口两项（决策者裁决）

1. **`editor_set_material_3d.material_slot` 改成整数**（**批准**）：契约现在把它声明为 **string**，
   而引擎 API 取的是 **int 表面索引**（`MeshInstance3D::set_surface_override_material(i, …)`）。
   → 走 **`SCHEMA_OVERRIDES`**（`mode=replace`，理由**逐字引用**被替换成员）把它改成 **`integer`**
   （语义：表面索引；省略 = 第一个表面），**重生成契约 + 更新全部指纹**，门① 逐字通过。
   **并顺带做一次普查**：在**已实现 + 未实现**的全部 171 条里找出**其它「索引/序号被声明成字符串」**的参数
   （迁移源用 GDScript `str()` 的历史包袱）→ **列清单**；本批只修这一个（其余留待对应批次，报告给出清单即可）。
2. **`editor_add_audio_bus.after_bus_index` 越界 → `-32602`**（**批准**，不做静默 append/clamp）：
   与「不得静默重解释」一致。**无需改动**，只在报告里确认。

3. **门⑥ 引脚行号只是文档**：`PINNED` 的 `line` 字段**仅供参考**，**位移不失败**。
   → **后续批次无需为了对齐行号去改它**（除非顺手）。批次的义务是：**新增收窄点必须标注** + **跑门⑥ 三段式**。

## 1. B5 批次 3：15 个工具（**以 `docs/tool-groups-b5.json` 为准**）

| 组 | 数量 | 工具 |
|---|---|---|
| `editor_tilemap_write` | 3 | `editor_remove_all_tilemap_cells`、`editor_set_tilemap_cell`、`editor_set_tilemap_cells_in_rect` |
| `editor_tilemap_read` | 3 | `editor_get_tilemap_cell`、`editor_get_tilemap_info`、`editor_get_tilemap_used_cells` |
| `editor_shader_write` | 2 | `editor_set_shader_material`、`editor_set_shader_param` |
| `project_shader_write` | 2 | `project_create_shader`、`project_edit_shader` |
| `project_shader_read` | 2 | `project_get_shader_params`、`project_read_shader` |
| `editor_physics_write` | 1 | `editor_set_physics_layers` |
| `editor_physics_read` | 2 | `editor_get_collision_info`、`editor_get_physics_layers` |

## 2. **两个 `fix_implementation_first`（必须先红后修）**

1. **`editor_set_tilemap_cell`（旧 `set_tilemap_cell`）**：迁移源**没有正确校验/使用 source/atlas 坐标**，
   导致**写入错误的数据**（数据破坏类）。→ **先写红测试**证明「写入的格子与请求的不一致 / 越界未拒绝」，
   再按引擎的 `TileMapLayer::set_cell(coords, source_id, atlas_coords, alternative)` 语义修好。
2. **`editor_set_tilemap_cells_in_rect`（旧 `set_tilemap_cells`）**：同族，**批量数据破坏**风险更高。
   → 红测试要覆盖「**故意坏的中间元素**」：批量必须**全成功或全回滚**（与 TASK-017 的批量语义一致），
   `remove_all_tilemap_cells` 必须给出**真实删除计数**。
   **注意**：族内工具（读族）必须能**读回**写族写的内容（写→读互验链），否则数据破坏无法被发现。

## 3. **E-5（M4c 遗留，本批必查）**：`editor_set_shader_param` 的写路径

迁移源用**复合属性路径**直写（类似 `material:shader_parameter/uv1_scale`），而引擎有
**`ShaderMaterial::set_shader_parameter(name, value)`**。
→ **必须实测**「复合路径直写」到底**是否真的生效**（这是 M4c 未证实的点）：
- 若生效：说明两条路都行，**仍应改用引擎 API**（更可诊断、错误更清晰），并给出前后对照；
- 若**静默失效**（写进去读不回来）：那就是**第三类「报成功但没发生」**——**红测试先行**，修好，并记入手册 §6.6。
**`editor_set_shader_material`** 必须**真正替换**（`ShaderMaterial` 与 `BaseMaterial3D` 的区别、以及**多重材质/槽位**都要按引擎语义）。

## 4. 通用要求

1. 每工具一行「引擎依据」（API + 文件:行）；与迁移源差异**必须给理由**。
2. **≥1 条跨 ≥4 工具的零字符串手术链**（逐步字符串操作 0 次）。
3. 三类证据（成功 / 缺参 `-32602` / 底层失败）+ **每组一条跨工具活证据链**。
4. **不得假成功**：未知 shader 参数 / 未知 layer / 不存在的 atlas 坐标 → 明确错误（`-32001`/`-32602`）。
5. 带**整数 default** 的新工具套用 TASK-033/034 的归一化办法。
6. `docs/tool-groups-b5.json` 里这 7 组置 `implemented=true`（只改这些布尔）。
7. **`scope` 纪律**：`editor_*` 缺席于 9889；`project_*` 按映射 scope 两端可见。
8. **门⑥ 三段式** + §22.3b 规则 4（新增收窄点逐条列）。
9. **D86 结论有效性纪律**（引用别处结论须标提交锚点 + 复测 + 过期 append-only 勘误）。

## 5. 门

- 第 0 步：`scripts/build_local.cmd -Force`（`tests=yes`）重建 + 校验 `--version` == HEAD（**从 cmd 启动**）。
- 五道门（**门①按 7 组各跑一次**）+ 门⑥ 三段式。
- 回归：重跑 `mcp034`/`mcp033`/`mcp032`/`mcp030` 证据脚本。

## 6. 报告

按手册 §4（含「引擎依据」列），写到 `docs/reports/REPORT-035-b5-tilemap-shader-physics.md`；另加：
「两个 fix-first 的红→修全程」「`set_shader_param` 复合路径实测结论（生效/失效）」
「`material_slot` 整数化 diff + 「索引声明成字符串」普查清单」「零字符串手术链」「B5 进度（44/58）」。
**返回值：≤15 行总结 + 报告路径。**