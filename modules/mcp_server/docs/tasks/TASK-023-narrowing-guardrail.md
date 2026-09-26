# TASK-023 — D-7（闸门未覆盖专用 setter 路径）+ D-15（双精度 latent）+ **结构性收窄点护栏**

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（通用规范，自包含；**§6 总纲与 §6.10 已改为
> 「引擎源码是第一参考源、顺手性是验收条款」**），再读本文件。
> 报告写到 `docs/reports/REPORT-023-narrowing-guardrail.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 来源与**方法论教训**（先读懂）

M4 第三次独立验收仍判 `fail`（`docs/reports/REPORT-AUDIT-M4c.md`）。核心缺陷 **D-7**：

> **同一类缺陷已出现第 4 种形态**：容器元素 → 复合值分量 → 标量成员 → **专用 setter 路径**。

根因：闸门挂在 `coerce_to_property_type` 上，因此**只覆盖走 `Object::set()` 的属性写**；
凡「**先算出值、再调用专用 setter**」的路径全都绕过它。
→ **本次不只修实例，必须修「方法论」**：加**结构性护栏**，让**新的收窄点无法悄悄出现**。

## 1. D-7（high）：把闸门铺到专用 setter 路径

已实测绕过点（**必须逐条修**，并**自己找出其余**）：
- `editor_set_viewport_3d_camera`：`position` / `rotation_degrees`（`editor_write_scene_editor.cpp:149` 的
  `Vector3((real_t)…)`）→ `code=0` 静默写 `inf`；`fov`（`:739`）同源但被引擎范围校验挡住（**仅作登记**）。
- `editor_setup_world_environment`：`bg_color`（`editor_node_setup.cpp:128` → `:339` 的 `Color(...)`）→
  `code=0`，且 **`background_color = Color(inf, 0, 0, 1)` 已被 `editor_save_scene` 写进 `.tscn`**。

要求：
1. 这些路径的**每个分量在写入之前**走同一道闸门（`value_fits_slot(..., REAL_T)`），
   不合法 → `-32602`；批量/跨场景路径保持**任何写入之前**拒绝。
2. **自己扫描全模块**找出**其它**「先算值再调专用 setter / 直接构造 `Vector2/Vector3/Color`」的点
   （验收方已给出候选行号：`editor_input_simulation.cpp:232-254`、`running_game_input.cpp:325/466`、
   `running_game_test_execution.cpp:117` 等），逐条判定：**需要修 / 不需修（说明为何该值不可能越界）**，
   并给出**清单**。**清单里不得有"未判"项。**

## 2. D-15（medium, latent）：拆开「`FLOAT32`」与「`REAL_T`」

`value_fits_slot` 的 `REAL_T` 分支在 `#ifdef REAL_T_IS_DOUBLE` 下**无条件 `return true`**，
但 **`Color` 分量恒为 `float32`**（`core/math/color.h:39-42`）、**`PackedFloat32Array` 元素恒为 `float32`**
（`_container_element_slot:850-851`）→ **双精度构建下同类静默 `inf` 会复活**。
→ 拆成**独立槽位**（如 `FLOAT32` 与 `REAL_T`），`Color` 分量与 `PackedFloat32Array` 元素用 `FLOAT32`（恒按 32 位判），
其余按构建的 `real_t`。本构建是单精度，故：
- **必须**在**代码层**把该分叉做成**与构建配置无关的正确性**；
- **明确声明**「本机无法构造双精度二进制做端到端验证」，并把这一点写成**风险登记**（不得声称已端到端验证）。

## 3. ★ 结构性护栏（本任务最重要的产出）

要求给出**可执行的护栏**，至少包含：
1. **收窄点清单**：全模块所有 `(real_t)` / `(float)` / `Color(` / `Vector2(` / `Vector3(` / `Vector4(` 的
   **构造或收窄点**，逐条标注：①是否经闸门（哪一处）；②为何不经闸门也安全（或已修）。
   建议做成 `modules/mcp_server/scripts/check_narrowing_points.py`（或 `.ps1`）**可重复执行**的检查：
   扫描源码 → 与清单比对 → **新增未标注的收窄点即失败**。
2. **设计条款**：写入 `docs/DESIGN-DETAIL.md`（**扩展 GDR-22 或新增 GDR-24**）：
   「**槽位判定必须覆盖不经 `Object::set()` 的专用 setter 路径**；
   任何新增收窄点必须在清单中显式标注经过的闸门」。
3. **门集成**：把该检查**纳入既有门**（例如 `accept_m1.ps1` 之外的独立脚本，并在 `PLAYBOOK` §3 的五道门里登记为
   「门⑥：收窄点清单检查」），使其在**后续批次**自动生效。

## 4. 证据形态（沿用 M4c 的要求，四条同时）

①`-32602`（或事务信封里同语义）；②**拒绝响应无值回显**（不得回显 `1e99999`）；
③**显式 `editor_save_scene` 后扫描 `.tscn`**：无 `inf`/`nan`/`Color(inf`，且 sha256 不变；
④**另一读工具**（模块读 + 独立 GDScript 求值）读到旧值未变；并给**合法值仍正常写入**的正例。
覆盖：`editor_set_viewport_3d_camera`（`position`/`rotation_degrees`/`fov`）、`editor_setup_world_environment`（`bg_color`）
+ 你新找到的**每一个**点。

## 5. 门

五道门（第 0 步：`scripts/build_local.cmd -Force`（`tests=yes`）重建 + 校验 `--version` == HEAD）
+ **新增的门⑥（收窄点清单检查）** + §4 的证据形态 + §5 的回归：
**必须重跑** M4c 的反例矩阵（`1e300`/`3.5e38`/`-3.5e38`/`"1e300"`/`1e-300`/`1e-46` × 5 条写路径）
与 D-5/D-6 段，确认**未回退**。

## 6. 报告

按手册 §4（报告格式已含「引擎依据」列），写到 `docs/reports/REPORT-023-narrowing-guardrail.md`；另加：
「收窄点清单（逐条判定）」「门⑥ 的实现与一次"故意新增未标注收窄点"的**红**演示」
「D-15 的分叉实现与**未端到端验证**的显式声明」「回归矩阵结果」。
**返回值：≤15 行总结 + 报告路径。**