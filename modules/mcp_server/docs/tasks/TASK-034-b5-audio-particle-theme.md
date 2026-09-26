# TASK-034 — B5 批次 2：音频 / 粒子 / 主题 / 场景 3D / 性能 15 工具 + **动画族 4 个 schema 缺口**（走 override）

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册），再读本文件。
> **引擎优先**（`DESIGN-DETAIL` §21/GDR-23）是本批的设计纪律；顺手性见 **§23/GDR-25**；门⑥ 见 **§22.3/§22.3b**。
> 报告写到 `docs/reports/REPORT-034-b5-audio-particle-theme.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 先做：动画族 **4 个 schema 缺口**（决策者已批准走 override）

TASK-033 上报：迁移源读了**契约未声明**的参数，导致**能力不可达**（探到「已声明但工具不兑现」的反面：
**工具真需要却没声明**）。它已备好**可直接粘贴的 `SCHEMA_OVERRIDES`**，本批收口：

1. `editor_add_state_machine_state` 的 `animation`（**不加就无法给新建的 Animation 状态指定动画** →
   动画链的一部分**结构性不可达**）；
2. `editor_set_blend_tree_node` 的 `animation`（同理）；
3. `editor_add_state_machine_transition` 的 `xfade_time`；
4. `editor_add_state_machine_transition` 的 `priority` / `advance_condition`（以 TASK-033 报告的准备稿为准）。

**要求**：
1. 走 **`SCHEMA_OVERRIDES`**（`mode=replace`，理由**逐字引用被移除/受影响的成员**）+ 必要时 `DESCRIPTION_OVERRIDES`；
2. **重生成契约 + 更新全部指纹**；**不得手改契约文件**；
3. **门① 逐字通过**；并给出**结构化 diff** 证明**只**动这几个字段 + `_meta`；
4. **行为证据**：`animation` 声明后真的能把动画**喂给新建状态**（读回状态→动画名，并**原样喂回**其它工具）；
   给出**不可达 → 可达**的前后对照（这就是本项的价值证明）。

## 1. B5 批次 2：15 个工具（**以 `docs/tool-groups-b5.json` 为准**）

| 组 | 数量 | 工具 |
|---|---|---|
| `editor_audio_write` | 4 | `editor_add_audio_bus`、`editor_add_audio_bus_effect`、`editor_add_audio_player`、`editor_set_audio_bus_property` |
| `editor_audio_read` | 2 | `editor_get_audio_info`、`editor_get_audio_bus_layout` |
| `editor_particle_write` | 4 | `editor_create_particles`、`editor_set_particle_preset`、`editor_set_particle_color_gradient`、`editor_set_particle_material` |
| `editor_particle_read` | 1 | `editor_get_particle_info` |
| `editor_theme_write` | 1 | `editor_set_control_theme` |
| `editor_scene_3d_write` | 1 | `editor_set_material_3d` |
| `editor_profiling_read` | 1 | `editor_get_performance_monitors` |
| `editor_navigation_read` | 1 | `editor_get_navigation_info` |

**特别注意（来自 M4c 对迁移源的审查）**：
- **`editor_add_audio_bus` / `editor_set_audio_bus_property`**：`AudioServer` 的**总线索引与名字**语义要按引擎来
  （迁移源可能按名字或索引混用）；**总线的属性是有类型的**（`volume_db`、`solo`、`mute`、`send`…），
  写入必须走**同一道闸门**（`value_fits_slot` + 类型判定），不得静默接受错值。
- **`editor_set_audio_bus_property` 的越界/未知属性** → `-32001`/`-32602`（不得假成功）；
  `send` 这类**指向另一条总线**的属性要**可链式喂回**。
- **`editor_set_particle_color_gradient`**：`Gradient` 是资源 → 按 **§23.4/§23.5** 的资源形状处理（读回可写回）。
- **`editor_set_particle_material` / `editor_set_material_3d`**：**引擎有槽位概念**
  （`MeshInstance3D::set_surface_override_material(i, mat)`）；迁移源**读了 `material_slot` 却硬编码 0**
  （M4c 的 E-4）→ **必须真正尊重槽位**，并在报告里给「不同槽位写不同材质 → 读回分别正确」的证据。
- **`editor_set_shader_material` / `editor_set_shader_param` 属批次 3**，但如果你在本批碰到同类槽位/参数路径，
  按同一原则处理并记录。

## 2. 通用要求

1. **每工具一行「引擎依据」**（API + 文件:行）；与迁移源不同之处**必须给理由**（差异是常态）。
2. **≥1 条跨 ≥4 工具的零字符串手术链**，逐步标出调用方字符串处理次数（目标 0）。
3. **三类证据**（成功 / 缺参 `-32602` / 底层失败）+ **每组一条跨工具活证据链**。
4. **创建类必须读回核实**（例如 `editor_add_audio_player` 后节点真的在树里且类型正确）。
5. **整数 `default` 的归一化**：TASK-033 发现引擎的 JSON 往返会把整数默认值拉平为 `0.0`（导致门① 比对失败）→
   本批**任何带整数 default 的新工具**必须套用同一办法（TASK-033 报告 §5.4.2 的 `_schema_with_integer_position_defaults` 同构做法）。
6. `docs/tool-groups-b5.json` 里这 8 组置 `implemented=true`（**只改这些布尔**）。
7. **`scope` 纪律**：`editor_*` 必须**缺席于 9889**；`project_*` 按映射的 scope 两端可见。
8. **门⑥ 三段式**；若引入收窄点，逐条列「新增点 × 经过的闸门 × 证据」（§22.3b 规则 4）。
9. **结论有效性纪律（D86）**：引用别的报告的结论必须标明**测自哪个提交**、参考前**复测**、过期就 **append-only 勘误**。

## 3. 门

- 第 0 步：`scripts/build_local.cmd -Force`（`tests=yes`）重建 + 校验 `--version` == HEAD（**从 cmd 启动**）。
- 五道门（**门①按 8 组各跑一次**）+ 门⑥ 三段式。
- 回归：重跑 `mcp033`/`mcp032`/`mcp030` 证据脚本确认未回退。

## 4. 报告

按手册 §4（含「引擎依据」列），写到 `docs/reports/REPORT-034-b5-audio-particle-theme.md`；另加：
「4 个 schema override 的 diff 与不可达→可达证据」「15 工具 × 引擎依据 × 自然契约 × 差异理由」
「零字符串手术链」「B5 进度（29/58）」。**返回值：≤15 行总结 + 报告路径。**