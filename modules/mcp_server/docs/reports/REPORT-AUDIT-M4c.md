# REPORT-AUDIT-M4c — 里程碑级独立验收（**第三次**）：B3+B4（47 个工具）

- 任务书：`docs/tasks/TASK-AUDIT-M4.md`（§2 开头「本轮为第二次验收」的说明 + **新增 §2.F 顺手性条款**）
- 前两轮报告：`docs/reports/REPORT-AUDIT-M4.md`（首轮 `fail`：D-1/D-2/D-3）、
  `docs/reports/REPORT-AUDIT-M4b.md`（第二次 `fail`：D-4 high / D-5 medium / D-6 medium）
- 验收方：**独立验收工程师**（未参与实现；**未采信** `REPORT-0*.md` 与决策者结论；本报告所有结论均由本次自行运行产生）
- 日期：2026-09-22/23（本次会话）
- 仓库：`F:\RustProjects\godot-mcp-pro\code\godot`，分支 `feature/mcp-server-module`
- **被验二进制**：`bin\godot.windows.editor.x86_64.console.exe`
  - `--version` = `4.8.dev.custom_build.50aadecca`；`git rev-parse --short HEAD` = `50aadecca9`（**前缀一致**）
  - SHA256 = `B6A193E3DF934C1573EFF0A826F0EA015F53D7078A5D6B08229EC5994AE1D7BB`
- 临时工作根：`%TEMP%\audit-m4c\`（自建 harness `common.ps1` / `run.ps1` / `run2.ps1` / `run3.ps1` / `run4.ps1` / `gates.ps1` /
  `analyze_equality.py`、`evidence\*`、`results*.json`、`logs\`、本次 scratch 工程 `project\`）
- 工作树：开工时 `git status --porcelain` 仅 4 个**既有**未跟踪项（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、
  `install-deps-m0.cmd`）；HEAD 仍为 `50aadecca9e331338d9e484660a35952d96a9928`。**未修改任何被跟踪文件、未执行任何 git 写操作、未安装依赖。**
- 端口纪律：9877 全程属于用户 **PID 36392**（`Godot_v4.7.1-stable_mono_win64`）；本次仅用 9888 / 9889（外加被 `editor_play_scene`
  拉起的子进程使用 scratch 工程自己配置的 9891 —— 见 D-13，收尾已确认无监听、无孤儿）。

---

## 0. 开工第一步：`--version` 与 HEAD 校验（**不一致，已按规定脚本重建**）

开工时 `--version` = `4.8.dev.custom_build.861c1cde1`，HEAD = `50aadecca9` → **不一致**
（二进制停在 TASK-022 的**任务书提交** `861c1cde1a`，而 HEAD 已包含 TASK-022 的三个实现提交）。

按任务书用 **`modules/mcp_server/scripts/build_local.cmd -Force`（`tests=yes`）** 重建：

```
cd /d F:\RustProjects\godot-mcp-pro\code\godot
modules\mcp_server\scripts\build_local.cmd -Force
 -> build_local: exit code = 0
 -> log = %TEMP%\mcp_server_build_local.log   (FORCE: stale test objects deleted ×2 ; EXIT_CODE=0 ; 未抑制 scons 输出)
```

重建后 `--version` = `4.8.dev.custom_build.50aadecca` == HEAD 前缀（`S0_version` PASS），SHA256 如上。
`-Force` 在本轮**确实删除了**两个陈旧 test 对象（`bin\obj\modules\mcp_server\tests\test_mcp_server.windows.editor.x86_64.obj`、
`bin\obj\tests\test_main.windows.editor.x86_64.obj`），因此门③ 的 190 个用例是真跑的（M4b risk 5 的假绿陷阱本轮被 `-Force` 关闭）。

> 本报告全部证据均在上述二进制上采集。

---

## 1. 结论摘要

| 交付 | 结论 |
|---|---|
| **① 闭合复核** | **D-4 的 5 条写路径全部真闭合**（6 个反例 × 5 条路径 × 四条证据形态全成立，合法对照正常写入）；**D-5 真闭合**（`changed`/`properties_set`/`ignored` 与独立 GDScript 回读一致）；**D-6 真闭合**（游戏侧写 `user://`、编辑器侧读、缺失/空/坏 JSON 三种诚实失败、`clear` 跨进程）。 |
| **① 但覆盖面没有清零** | 自己找到 **D-7（high）**：统一收窄闸门**没有覆盖全部写路径** —— `editor_set_viewport_3d_camera`（`position`/`rotation_degrees`）与 `editor_setup_world_environment`（`bg_color`）仍然把 `1e300`/`3.5e38` **静默写成 `inf` 并回答 `code=0`**，响应里出现 M4b 用来判 fail 的那个形状（`"x":1e99999`），且 `bg_color` 的 `inf` **已经落进保存后的 `.tscn`**（`background_color = Color(inf, 0, 0, 1)`）。 |
| **② 顺手性（GDR-23）** | **fail**：E-1 / E-2+E-8 / E-3 / E-6 / E-9 / E-10 六项经引擎源码级证据 + 线上实测**判为缺陷**；E-4 / E-5 判 **N/A**（工具属 B5，未注册）；E-7 的**前提不成立**（实现用的是 `node->set_script()`，不是 `node.set("script", …)`）。另自找 G-1（无子属性路径）、G-2（`project_get_scene_dependencies` 的 `path` 是 `uid://`）、G-3（`clear` 默认删共享报告文件）、G-4（同族返回形状不一致）。 |

**总 verdict：`fail`**（诚实性 + 顺手性两类；工程门 / 全量对等 / 安全与事务 / 延迟通道 / 端口纪律五类 pass）。

---

## 2. ① 闭合复核（D-4 / D-5 / D-6）

### 2.1 方法

- 5 条写路径 = M4b 判 D-4 时用的那 5 条：`editor_set_node_property`、`editor_set_node_property_batch`、
  `editor_add_nodes_batch`、`running_game_set_node_property`（9889）、`project_set_node_property_across_scenes`
  （`dry_run=false, force=true`，**真的写盘**）。
- 反例 = `1e300` / `3.5e38` / `-3.5e38` / `"1e300"` / `1e-300` / `1e-46`；合法对照 = `1e30` / `1e-30` / `3.4e38`。
- **四条证据形态**（任务书要求同时成立）：① 错误码；② 拒绝响应**无值回显**（无 `result` 载荷、`error.data` 无 `new_value`/`old_value`/`stored`）；
  ③ **显式 `editor_save_scene` 后** `.tscn` 字节内无 `inf`/`nan`/`1e99999` **且 sha256 与基线相同**；
  ④ **另一读工具**读到旧值：编辑器侧 = `editor_get_node_properties` + `editor_execute_gdscript`（独立求值通道）；
  游戏侧 = `running_game_get_node_properties` + `running_game_execute_gdscript`；跨场景路径 = 编辑器侧 GDScript
  `load("res://xscenes/good.tscn").instantiate()` 直接读**文件内容**。
- 关于「另一读工具为何对本例有效」：本例旧值是 `0.5`，**有限且可序列化**，所以两条通道都能看见它；
  且 `str(Actor.rotation)` 能显式拼出 `inf`（`serialize_variant` 对非有限 float 会退化成 `null`，只用模块读工具看不见 `inf`
  —— 这正是 D-4 当年能躲过旧判据的原因，故两条通道都保留）。

### 2.2 D-4：5 条写路径 × 6 反例（全部闭合）

`Actor.rotation`（`Node2D` 的 `real_t` 成员，旧值 `0.5`）；**sha 基线 `851828d4eb7112c14ce521023d77235388e9a63dd9ddb4850f535fddd2a4b7af`**
（拒绝后 `editor_save_scene` 两次，前后同一 sha）：

| 路径 | 6 个反例的错误码 | ② 无值回显 | ③ save 后文件 | ④ 另一读工具 |
|---|---|---|---|---|
| 1 `editor_set_node_property` | 全部 **-32602** | 全部成立（消息点名引擎会写的 `inf`/`0`） | sha 相同、无 `inf`/`nan` | props `0.5` + gd `0.5` |
| 2 `editor_set_node_property_batch`（`node_type=Node2D`） | 全部 **-32602**（`…write refused before any node was written`） | 全部成立 | sha 相同、无 `inf`/`nan` | props `0.5` + gd `0.5` |
| 3 `editor_add_nodes_batch` | 全部 **-32602**（`nodes[0]:` 定位） | 全部成立 | sha 相同、无 `inf`/`nan`、**场景树里没有 `D4Node*`** | gd `0.5` |
| 4 `running_game_set_node_property`（9889） | 全部 **-32602** | 全部成立 | （游戏侧无 save 工具；由路径 1/2/3/5 覆盖文件形态） | game props `0.5` + gd `0.5` |
| 5 `project_set_node_property_across_scenes`（写盘） | 外层 **-32000**，`data.scenes.errors[0].reason` **就是同一条 -32602 语义**（`does not fit in the 32-bit float slot` / `too small for`），`data.suggestion` 含 `Nothing was written` | 全部成立 | `xscenes/good.tscn` sha **不变**、无 `inf`/`nan` | `load()` 读到 `0.5|0.5` |

**合法对照（回归）**：路径 1/4 的 `1e30`·`1e-30`·`3.4e38` 全部 `code=0` 且回显有限；路径 5 的三个对照**真的改盘**
（sha `a45e61fd…` → `04fbb104…` → `da893b25…` → `c0f9b5bb…`），`load()` 读回 `1e30` 对应的 float32 值。

原文（节选，路径 1 的溢出与下溢）：

```
[A1_1e300]  resp: {"error":{"code":-32602,"message":"Parameter 'value' is the number 1e+300, which does not fit in
              the 32-bit float slot this value is copied into … the engine's own copy would write inf …"}}
[A1_1e-46]  code=-32602 … "which is too small for the 32-bit float slot … would write 0 …"
[A1c_1e30]  resp: {"new_value":1000000015047466219876688855040.0,"node_path":"Actor","old_value":0.5,…}
[A5_1e300]  outer code=-32000, data.scenes.errors[0].reason = 同一条 -32602 语义,
            data.suggestion = "Nothing was written. …"
```

**补充覆盖验证**（我另测了 4 条不被 M4b 点名的写路径，以防「只有 5 条被修」）：
`project_create_resource`（`Curve2D.bake_interval=1e300` → **-32602**）、
`project_edit_resource`（D-5 段）、`editor_add_resource_to_node_property`（M4b 已覆盖）、
`editor_setup_collision_shape`（`shape_params={size:{x:1e300,y:10}}` → **-32602**，合法 `{x:32,y:10}` → `code=0`）。

> **D-4 本体（M4b 的 D-4）结论：已闭合。** 但「覆盖全部写路径」不成立 → **D-7**。

### 2.3 D-4 的覆盖声明不成立 → **D-7（新，high）**

`REPORT-022 §2.3` 声称「模块里**每一个**把 JSON 值交给 `Object::set()` 的入口，其最后一步都是 `coerce_to_property_type`」，
因此「不可能存在『转换过了但槽位没判』的路径」。本轮找到两条**不经 `coerce_to_property_type`** 的写路径：

| 工具 | 我发出的请求 | 返回 | 响应原文 | 另一读工具（GDScript） |
|---|---|---|---|---|
| `editor_set_viewport_3d_camera` | `position={"x":1e300,"y":0,"z":0}` | **code=0** | `{"fov":70.0100021362305,"position":{"x":1e99999,"y":0.0,"z":0.0},…}` | `camera.global_position` = **`(inf, 0.0, 0.0)`** |
| `editor_set_viewport_3d_camera` | `rotation_degrees={"x":3.5e38,…}` | **code=0** | `…"rotation_degrees":{"x":1e99999,…}` | `camera.rotation_degrees` = **`(inf, 0.0, 0.0)`** |
| `editor_setup_world_environment` | `bg_color={"r":1e300,"g":0,"b":0}` | **code=0**（`setup:true`） | `{"environment_created":true,"setup":true,…}` | `editor_save_scene` 后 `main.tscn` 内 **`background_color = Color(inf, 0, 0, 1)`** |

- 正向对照：`bg_color={"r":0.1,"g":0.2,"b":0.3}` → `code=0`，文件里是 `background_color = Color(0.1, 0.2, 0.3, 1)`
  —— 说明该路径本身工作正常，缺陷**只是缺闸门**。
- `fov=1e300` 是**诚实**的（引擎 `Camera3D::set_fov` 自带 1–179 的范围校验，非法值被丢弃，回显写后真值 `70.01`）——
  这反证了「不是工具类的问题，而是这两处**参数收窄**漏判」。
- **落点（行号级）**：
  - `modules/mcp_server/tools/editor_write_scene_editor.cpp:123-151` 的 `_optional_vector3`：
    `r_out = Vector3((real_t)components[0], (real_t)components[1], (real_t)components[2]);`（**:149**）——
    `double → real_t` 直接收窄，无任何槽位判定；
  - 同文件 `:739` `camera->set_fov((real_t)fov);`；
  - `modules/mcp_server/tools/editor_node_setup.cpp:105-130` 的 `_color_from_json`：
    `r_out = Color(values[0], values[1], values[2]);`（**:128**，`double → float` 分量），随后 `:339/:345` `environment->set_bg_color/set_ambient_color`，
    `world_env->set("environment", environment)`（**:324**）。
- **为什么这是 high**：这就是本项目最核心的诉求（「值表达不出来 → 引擎按自己的语义写 → 工具报成功」），
  形态与 M4b 判 fail 的 D-4 **完全一致**（`code=0` + 回显 `1e99999` + 落盘 `inf`），只是换了两个工具。
  它同时是 `REPORT-022` §2.4「同类面清零」与 §2.3「该处覆盖全部写入路径」两个断言的**反例**。

### 2.4 D-5：`project_create_resource` 的回读/`ignored`（**已闭合**）

| 输入（`type=Curve`） | 工具返回 | 独立 GDScript 回读 |
|---|---|---|
| `min_value=5.0` | `properties_set=[]`；`changed.min_value={old:0.0,new:0.990000009536743}`；`ignored.min_value={requested:5.0,stored:0.990000009536743,reason:"…clamps or refuses…"}` | `load().min_value` = `0.990000009536743`（**一致**，非谎报） |
| `min_value=0.25,max_value=0.75,bake_resolution=5` | `properties_set` 3 项；`ignored={}` | `0.25|0.75|5` |
| `min_value=1e300` | **-32602**（闸门在**创建文件之前**拒绝） | `FileAccess.file_exists("res://cv_d5_c.tres")` = **`false`** |
| `bake_resolution=3000000000`（`int` 成员，声明为 WIDE 边界） | `properties_set=[]`；`changed.bake_resolution={old:100,new:100}`；`ignored.bake_resolution={requested:3000000000,stored:100}` | `load().bake_resolution` = `100`（**引擎拒绝越界，工具如实汇报未设置**） |
| `project_edit_resource({min_value:0.5})`（同口径参照） | `changed={min_value:{old:0.25,new:0.5}}` | `0.5` |

`ignored` 与独立回读**逐条一致**，`properties_set` 是「回读=请求」的子集 —— M4b 的 D-5（未回读的断言）**已闭合**。

### 2.5 D-6：跨进程测试报告（**已闭合**）

| 检查 | 我自己的实测 |
|---|---|
| 游戏侧跑断言 | `running_game_assert_node_state`（→ 见下注）：报告里 `total=2`、两条 `details` 均带 `expected`/`actual`/`reason`/`operator`/`resolved_node_path` |
| 桥接文件 | `C:\Users\wyl\AppData\Roaming\Godot\app_userdata\M4C-AUDIT\mcp_test_report.json` 存在（sha `a7acf205…`） |
| 编辑器侧读 | `editor_get_test_report{clear:false}` → `total=2, passed=0, failed=2, source="game_process_file", report_path="user://mcp_test_report.json", report_format_version=1, report_source_process="game", report_written_at_unix=1790092613` |
| **缺失诚实** | 删掉桥接文件后再读 → `total=0, no_results=true, report_file_present=false, report_unavailable_reason=…does not exist`（`C_missing_honest` PASS） |
| **空文件诚实** | 写 0 字节 → `total=0, no_results=true` + 对应 reason（`C_empty_honest` PASS） |
| **坏 JSON 诚实** | 写 `{ this is not json` → `total=0, no_results=true` + `…is not valid JSON`（`C_malformed_honest` PASS） |
| `clear` 跨进程 | 第一次读回 `total≥2` 且 `cleared` 列明两侧；文件被删除；紧接着再读 `total=0, no_results=true, report_file_present=false`（`C_clear_cross_process` PASS） |

> **注（我自己的装置错误，如实记录）**：`C_game_assertions_ran` 判 FAIL，因为我在路径 4 的**合法对照**里把游戏侧
> `Actor.rotation` 留在 `3.4e38`，于是「应当通过」的那条断言也失败了（原文
> `pass=false fail=false reason="expected rotation eq 123, found 339999995214436424907732413799364296704.0"`）。
> 这是**我的期望写错**，不是产品缺陷：报告本身正确地把两条都记为 `failed`，`C_editor_sees_game_report` / 桥接文件 / 三个诚实失败用例全部 PASS。

### 2.6 自找的同族新面（除 D-7 外）

| # | 面 | 实测 | 判定 |
|---|---|---|---|
| N1 | `position=[1e300,1]`（JSON 数组给 `Vector2`） | **-32602**，消息说明 `can_convert(Array→Vector2)` 不成立、会变零向量 | 响亮拒绝，非缺陷 |
| N2 | `v2i={"x":3000000000}` | **-32602**（点名 `-1294967296` 低 32 位） | 已闭合 |
| N3 | `v4={"x":1e300,…}` | **-32602**（`value.x`） | 已闭合 |
| N4 | `v4={x,y,z}`（缺 `w`） | **-32602**，消息点名四个分量 | 已闭合 |
| N5/N6 | `pv2=[{"x":1e300,…}]` / `pv4=[…]` | **-32602**（`value[0].x`） | 已闭合 |
| N7 | `pi32=[3000000000]` | **-32602**（`value[0]`，低 32 位） | 已闭合 |
| N8 | 另一个 `float` 导出（`num`）`1e300` | **-32602** | 已闭合（不止 `rotation` 一个属性） |
| N9 | `rect={"x":1e300,…}`（`Rect2`） | **-32602**（`can_convert(Dictionary→Rect2)` 不成立） | 响亮拒绝 |
| N10 | `color={"r":1e300,…}` | **-32602**（`value.r`） | 已闭合 |
| N11 | `int` 脚本变量 `i32=3000000000` | `code=0`，回显 `new_value=3000000000`（脚本变量是 Variant int64，**真的能存**） | 非缺陷（且回显是写后真值） |
| N12 | `project_create_resource(Curve2D.bake_interval=1e300)` | **-32602** | 资源写路径也受同一闸门 |
| N14 | 边界：`3.4e38` 接受 / `3.5e38` 拒绝 | `3.4e38` → `code=0`；`3.5e38` → **-32602** | 闸门按**槽位**判、不是按「数大」判 |
| **D-15**（源码级，本构建不可观测） | `value_fits_slot(REAL_T)` 在 `REAL_T_IS_DOUBLE` 下**无条件 `return true`**（`tool_helpers.cpp:771-775`），但 `Color` 的分量**恒为 `float`**（`core/math/color.h:39-42` `float r,g,b,a`）、`PackedFloat32Array` 元素**恒为 `float`**（`_container_element_slot` 把 `PACKED_FLOAT32_ARRAY → REAL_T`，`tool_helpers.cpp:850-851`；`Color` 分量在 `running_game_node_write.cpp:261-264` 也标成 `COMPONENT_WIDTH_REAL`） | 单精度构建下正常；**双精度构建（`precision=double`）下同一类静默 `inf` 会复活**（`1e300 → Color(inf,…)`、`1e300 → PackedFloat32Array` 元素 `inf`） | **潜在缺陷**（medium，源码级；本次未构造双精度二进制，见 §7 `unconfirmed`） |

---

## 3. ② 顺手性审计（GDR-23，§2.F）

> 判据：①引擎对应的 API 一次能做到什么（**行号级证据**）；②参数/返回是不是引擎自然形态；③返回值能否直接喂回下一个工具。

### 3.1 E-1 … E-10 逐条结论

| # | 结论 | 引擎证据（行号） | 我的实测证据 | 严重度 |
|---|---|---|---|---|
| **E-1** | **缺陷（且比「恒为空串」更糟）** | `scene/resources/resource_format_text.cpp:919` `ResourceLoaderText::get_dependencies()`；**:960-968** `if (p_add_types) path += "::" + type;` 再 `path += "::" + fallback_path`；`core/io/resource_loader.h:266`（静态 `get_resource_type`）、`:270`（`get_dependencies(..., bool p_add_types = false)`）；`:83/:87` 的虚接口同 | 保存后的 `main.tscn`（带 `uid=` 的 `ext_resource`）→ 工具返回 `{"count":1,"dependencies":[{"path":"uid://c7mt5x5j361vt","type":"res://main.gd"}],"path":"res://scenes/main.tscn"}`：**`type` 是 fallback 路径而不是类型**（`uid://x::::res://main.gd` 按 `"::"` 切分后 `parts[2]` 恰好是 fallback），**`path` 是 `uid://`** 而不是 `res://`。模块注释（`project_read_analysis.cpp:733-737`）自认「`add_types=false` 第三段通常没有，type 为空」——即在**有意复刻迁移源的缺陷**，而引擎一次调用就能给出类型 | **无法直接喂回**：所有其它工具以 `res://` 为入参，调用方必须额外调 `project_convert_uid_to_path`；`type` 字段要么空、要么是别的路径 | medium |
| **E-2** | **缺陷（确定性/可复制性），但「每次运行都变」**未复现**** | `scene/main/node.h:573` `NodePath get_path_to(RequiredParam<const Node> p_node, bool p_use_unique_path = false)`；`:554` `set_unique_scene_id(int32_t)`、`node.cpp:2139` `get_unique_scene_id()`（本 fork 有**每节点稳定 id**，保存为 `.tscn` 里的 `unique_id=…`） | `editor_get_scene_tree` 返回：`/root/@EditorNode@20539/@Panel@14/@VBoxContainer@16/…/@EditorMainScreen@166/2D/…/@SubViewport@9998/Main/Actor`（含 8 个内部 @-节点与 id）。**同一进程内两次调用逐字节相同**；**重启编辑器进程后再采集也相同**（`E2R_same_or_not identical=True`）。对照：游戏侧 `running_game_get_scene_tree` / 报告里的 `node_path` 是 `/root/Main/Actor`（稳定、可读） | 输出是**编辑器 UI 布局的内部路径**，非契约稳定标识；与「节点路径（相对于场景根节点）」的契约口径**不一致**（同一模块的成功响应 `node_path` 却是 `"Actor"`） | medium |
| **E-3** | **缺陷（形状分裂）** | `tools/tool_helpers.cpp:94-200` `serialize_variant`：`VECTOR2/2i/3/3i/COLOR/RECT2` 有专门分支（→ 对象），**`VECTOR4` 与所有 packed 数组落到 `default:` → `p_value.stringify()`（→ 字符串）**（**:196-198**） | 同一次 `editor_get_node_properties('.')`：`{"position":{"x":0.0,"y":0.0}, "v2i":{"x":1,"y":2}, "color":{…}, "rect":{…}, "v4":"(5.0, 6.0, 7.0, 8.0)", "pv2":"[(1.0, 2.0)]", "pv4":"[(1.0, 2.0, 3.0, 4.0)]"}`。写侧 `new_value` 也是字符串。消费者必须对「对象/字符串/null」三分支 | 同一类值两种形状；写 `{x,y,z,w}` 读回 `"(x, y, z, w)"`（**不可链式喂回**，需自行解析） | medium |
| **E-4** | **N/A（M4 范围内不存在该工具）** | 引擎正解：`scene/3d/mesh_instance_3d.cpp:375-383` `set_surface_override_material(int p_surface, …)`（`ERR_FAIL_INDEX` 按**表面索引**写） | 两端 `tools/list` 均**无**任何 shader 命名工具（9888 = 91、9889 = 53）。迁移源确有该缺陷：`godot_mcp_gdext/src/commands/scene_3d.rs:131` `let _material_slot = args.get("material_slot")…`（**读了不用**）、**:142** `mesh.set_surface_override_material(0, mat)`（**硬编码槽 0**） | 待 B5 实现时按引擎槽位 API 落地；**M4 不计缺陷** |
| **E-5** | **N/A（同上）** | 引擎正解：`scene/resources/material.h:126-127` `ShaderMaterial::set_shader_parameter(const StringName&, const Variant&)` / `get_shader_parameter`（并可用 `shader.get_shader_uniform_list()` 校验存在性） | 工具未注册（见上）。迁移源 `shader.rs` 用 `Expression` 复合路径直写，`set_shader_parameter` 不可达 | 同上 |
| **E-6** | **缺陷（读的是「别的进程的日志文件」）** | `tools/editor_read_scene_inspector.cpp:71` `static const char *LOG_PATH = "user://logs/godot.log";`（两个工具都只读它，**:94-119**）；`:103` 打不开就 `-32603`；**面板那半**（`editor_remove_output_log`）走的是编辑器进程内 `EditorLog`（`editor/editor_log.h:182` `add_message`）；`main.cpp:2287` `GLOBAL_DEF("debug/file_logging/enable_file_logging", false)`、`:2301` 仅当 `--log-file` 或该设置开启才写日志文件 | ① 第一次探测（证据文件 mtime **23:56:57**）→ 两个工具都 **`-32603 "cannot open the log file 'user://logs/godot.log'"`**；而 `user://logs\godot2026-09-22T23.56.58.log` 的 mtime 是 **23:56:58**（**晚 1 秒**）—— 即探测正好落在 `godot.log` 被**轮转/创建**的窗口里（编辑器和游戏进程共用同一个 `user://`）；② 文件存在后再探测（run3，0:05:47）→ `editor_get_output_log` 返回的是 **游戏进程**的行：`["[MCP] listening on 127.0.0.1:9889 (editor=false, tools=53)", …]`、`source:"log_file"`；`editor_get_errors` → `{count:0,errors:[]}` | 「清面板」与「读日志」是两个介质；同一 `user://` 文件被同工程的编辑器/游戏**共享并轮转**，编辑器端点会读到游戏进程的日志，且在轮转窗口里直接 `-32603` | medium |
| **E-7** | **前提不成立（非缺陷）** | 引擎语义正解确实是 `Node::set_script()`（`scene/main/node.cpp` 内的脚本实例化/`@tool` 处理） | 实现用的就是 `node->set_script(script)`：`tools/editor_script_write.cpp:259`（另有 `:157` 用于 `editor_execute_gdscript` 的临时实例），**没有** `node.set("script", …)` 的泛写；且 `editor_get_node_properties` 特意把 `script` 排除在列表面之外（`editor_node_read.cpp:198`） | **无缺陷**（E-7 描述的实现方式与代码不符） |
| **E-8** | **缺陷（错误消息带编辑器内部绝对路径）** | 同 E-2：`node.h:573` 有相对/唯一路径；模块自己在 `tools/running_game_node_write.cpp:490-495` 用 `node->get_path()` 拼路径（**:494**） | `editor_set_node_property(path='Actor', property='no_such_property_xyz')` → `-32001 "Property 'no_such_property_xyz' on node '/root/@EditorNode@20539/@Panel@14/…/@SubViewport@9998/Main/Actor' not found"`；而**成功**响应里 `node_path` 是 `"Actor"`（同一工具两套口径） | medium |
| **E-9** | **缺陷（读资源不给内容）** | 引擎一次可给：`ResourceLoader::load()` + `Resource::get_property_list()`（我的独立 GDScript 量到该 `Curve` 有 **7** 个 `PROPERTY_USAGE_STORAGE` 属性）；`project_read_scene_file_content` 只覆盖 `.tscn` | `project_read_resource("res://cv_d5_b.tres")` → `{"loaded":true,"path":"res://cv_d5_b.tres","type":"Curve"}` —— **零个属性值** | low-medium |
| **E-10** | **缺陷：结论「模块内不可修」不成立** | 引擎给了两条正路：**①** `editor/run/editor_run_bar.h:117` `public:` / **:123-125** `play_main_scene(bool p_from_native = false, const Vector<String> &p_play_args = Vector<String>())`、`play_current_scene(...)`、`play_custom_scene(...)`（**公开的额外参数**）；`editor_run_bar.cpp:355-364` `Vector<String> args = p_run_args; … editor_run.run(run_filename, write_movie_file, args);`。**②** 官方插件钩子：`editor_node.cpp:7797-7800` `call_run_scene()` → `editor/plugins/editor_plugin.h:218` `virtual void run_scene(const String &p_scene, Vector<String> &r_args)`（`editor_plugin.cpp:567`），在启动**之前**可改写参数 | 实测 `editor_play_scene{mode:'current'}` → `code=0`；被拉起的子进程命令行是
`godot.windows.editor.x86_64.exe --path C:/…/audit-m4c/project --remote-debug tcp://127.0.0.1:6007 --editor-pid 61484 --scene res://scenes/main.tscn`
—— **确实没有 `--mcp-port`**；而该子进程**监听在 9891**（= scratch 工程 `godot_mcp/port` 的值），证明它的端口来自**工程设置**而非编辑器参数。模块注释（`tools/editor_playback.cpp:64-69`）把这件事说成「模块自己不该发明端口」，但**引擎把参数接口是开着的** | medium |

### 3.2 我自己主动找的更多「按引擎源码本可以更顺手」项

| # | 项 | 引擎一次能做到什么 | 当前工具要几趟 | 严重度 |
|---|---|---|---|---|
| **G-1** | **没有子属性路径**：`editor_set_node_property` 不接受 `position:y` / `v4:x` | `core/object/object.h:697-698` `set_indexed(const Vector<StringName>&, …)` / `get_indexed`；`core/object/object.cpp:475-532` 实现（对 `Vector2` 走 `set_named("y", …)`，对字典/数组同样）；编辑器 Inspector 就是用这套 | 实测 `v4:x` → **-32001**、`position:y` → **-32001**（消息还把整条内部路径回显出来，见 E-8）。要改 `material.albedo_color`、`shape.radius` 这类子属性，调用方只能「建/取资源 → 写资源 → 再赋回节点」多趟 | medium |
| **G-2** | `project_get_scene_dependencies` 的 `path` 是 `uid://…`（E-1 的第二半） | `ResourceUID::get_singleton()->id_to_text/id_to_path`（core/io/resource_uid.h）、或直接 `get_dependencies(path, &deps, true)` + `parts[1]` 取类型 | 调用方必须再调一次 `project_convert_uid_to_path` 才能把结果喂给读文件/编辑类工具 | medium |
| **G-3** | `editor_get_test_report` 的 `clear` 默认 `true` 且**删除共享桥接文件** | —— | 多客户端（一个游戏进程 + 多个编辑器客户端）下，一次读取会清掉别的客户端还没读的那份报告（`REPORT-022` 风险 2 自认）；语义是「读」却带**破坏性副作用** | low（未实测多客户端，见 §7） |
| **G-4** | `editor_get_errors` 的返回**没有 `source` 字段**，`editor_get_output_log` 有（`"log_file"`） | —— | 两个同族工具的返回形状不一致；且都没有「这份日志是哪个进程写的」的字段（实测拿到的是游戏进程的行，见 E-6） | low |
| **G-5** | `editor_set_viewport_3d_camera` 不回答「哪些参数被引擎拒绝」 | 引擎 `Camera3D::set_fov` 会 `ERR_FAIL_COND`（1–179），`set_global_position` 不会 | `fov=1e300` → `code=0` + 回显未变的 `70.01`：调用方必须自己比较回显才知道**没生效** | low（与 D-7 同源） |
| **G-6** | `editor_add_mesh_instance` / `editor_add_gridmap` 等 setup 族只接受**节点级**参数，不接资源属性；改资源要另走 `editor_add_resource_to_node_property` | 引擎里这些都是同一句 `node->set(prop, resource)` + 资源属性赋值 | 两个工具两趟（可接受，但族内口径不齐） | low |

### 3.3 顺手性小结

**判据③（可链式喂回）全线告急**：`editor_get_scene_tree`（E-2）、`project_get_scene_dependencies`（E-1/G-2）、
`editor_get_node_properties` 的 `Vector4`/packed 形状（E-3）、`project_read_resource`（E-9）四类返回都不能直接喂回下一个工具；
**判据①（引擎一次能做到）**在 E-1/E-6/E-9/E-10/G-1 五处都有明确的引擎 API 反证。故 §2.F 判 **fail**。

---

## 4. 其它分类的复核（本轮自跑）

### 4.1 全量对等与 scope（pass）

用我自己的 `analyze_equality.py` 在**我自己的 `tools/list` 抓包**（`curl.exe -s -o`，9888 = 26351B sha `984a05c9…`、
9889 = 18401B sha `bb090b22…`）上比对，全部基于**解析后的 JSON 字段**（无 `-match`/文本包含）：

```
contract entries        : 171
implemented (manifest)  : 113
editor endpoint live    : 91      game endpoint live : 53      live union : 113
live union == implemented: True
missing from live / live but unimplemented / live but not in contract : [] / [] / []
expected editor 91, expected game 53 (only from tool-rename-map.json scope) ; 两向差集 []
verbatim diffs (description + inputSchema + 属性键集) : 0
重复名 0 ; 空名 0
```

跨端点：`editor_get_scene_tree` 在 9889 → **-32601**；`running_game_get_scene_tree` 在 9888 → **-32601**（`R4_cross_endpoint` PASS）。
未注册项：`live union == implemented` 已排除 3 个 B5 fix-first 与 2 个 `unregister_until_implemented`（另由
`check_tool_groups.py --check-completeness` 独立打印 `the 2 unregister… names are absent from the contract: PASS`）。

### 4.2 诚实性（B 段其它项）——4 个已修 fix-first 的复验

| 工具 | 结论 | 我自己的证据 |
|---|---|---|
| `editor_remove_output_log` | **真的清空面板** | 连续两次调用：`{"cleared":true,"log_was_empty":false,"log_is_empty":true}` → `{"cleared":true,"log_was_empty":true,"log_is_empty":true}`（跨调用可观测状态变化，常量伪造不出来） |
| `editor_set_auto_dismiss_dialogs` | **诚实拒绝** | `enabled="yes"` → **-32602**；合法 → **-32000 "Not implemented: editor_set_auto_dismiss_dialogs"**、`result` 为 null、**无请求值回显**（响应里只有工具名里的 `auto_dismiss` 字样，无字段回显） |
| `editor_disconnect_signal` | **真的只断指定的那条** | 连接后 `editor_list_signal_connections(node_path='Actor', signal_name='tree_exited').count` **3 → 2**；未命中 `target_path='./NoSuchTarget'` → **-32001 `Node './NoSuchTarget' not found`**（不误删） |
| `editor_get_test_report` | **诚实且现在可达** | 见 §2.5（跨进程报告 + 三种诚实空） |

### 4.3 延迟通道（pass）

| 检查 | 实测 |
|---|---|
| 超时 + 错误形状 | `running_game_find_node_when_available('/root/NeverEverA', timeout=1.0)` → **1036 ms** 返回 `-32000 "Deferred call timed out after 1000 ms: waiting for node '/root/NeverEverA'"` |
| 多 pending 不串线 | 第二次（`/root/NeverEverB`）消息**只含自己的节点名**（不含 `NeverEverA`） |
| pending 后常规请求仍毫秒级 | 紧接着 `running_game_get_scene_tree` → `code=0`，**26 ms** |
| pending 归零不崩 | 两次超时后端点继续正常服务（后续 scene tree / 断言 / 报告全部 `code=0`） |

### 4.4 工程门（pass，全部在 `50aadecca9` 的 `tests=yes` 二进制上串行运行、未抑制输出）

| 门 | 命令 | 结果 | 退出码 |
|---|---|---|---|
| ⓪ 构建绑定 | `build_local.cmd -Force` → `--version` | `EXIT_CODE=0`；`4.8.dev.custom_build.50aadecca` == HEAD `50aadecca9` 前缀 | 0 |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **190 cases / 190 passed / 0 failed**（1429 skipped）；**7716 assertions / 7716 passed / 0 failed**；`Status: SUCCESS!` | **0** |
| ④ 全引擎 | `--headless --test` | **1616 / 1616 / 0 failed / 3 skipped**；**431998 / 431998 / 0 failed**；`Status: SUCCESS!` | **0** |
| ⑤ 批收口 | `accept_m1.ps1` ×2 | 两次 **22/22 cases passed**；`[PASS] case*` 清单 20 行**逐行相同**（`p==q` 为 True）；两次都打印 `derived tool union : 113 tool(s) …` 与 `implemented tools = 91 (editor endpoint) / 53 (game endpoint); contract = 171` | **0 / 0** |
| tool-groups | `check_tool_groups.py --batch B3` / `--batch B4` / `--check-completeness` / 无参 | 四项 `… CHECK PASS`（B3 40、B4 7、`40+7+58=105` 两两不相交、B1 `41`） | 0 |

证据文件：`%TEMP%\audit-m4c\gate3.txt`、`gate4.txt`、`gate_groups.txt`、`accept1.txt`、`accept2.txt`、`gates_version.txt`。
（`accept_m1.ps1` 的 `$ToolNames` 派生性在 M4b §7.1 已用独立脚本证实无硬编码并集，本轮其输出仍打印 113/91/53 三方一致，未见回归。）

### 4.5 端口纪律（pass）

| 检查 | 结果 |
|---|---|
| 9877 全程 | 多次采样（含每次端点启停前后、`editor_play_scene` 前后、门脚本前后、收尾后）**始终 = 36392** |
| 测试端口 | 只用 9888 / 9889；`R2/R3/R4` 收尾后均为 `-1` |
| `editor_play_scene` 子进程 | 子进程 cmdline 被完整记录（PID 47384，见 E-10）；`editor_stop_scene` 后 **surviving descendants = 0**、9891 监听 = -1 |
| 孤儿进程 | 我方 launcher 的整棵进程树遍历，收尾后无存活子孙；全机仅剩用户自己的 36392 |
| 改动 | **未修改任何被跟踪文件**、**未执行任何 git 写操作**、未安装依赖（唯一的仓库新文件是本报告） |

---

## 5. `defects`

### D-7（severity: **high**）统一收窄闸门未覆盖全部写路径——两条路径仍把 `1e300` 静默写成 `inf`

- **claim**：`REPORT-022 §2.3` 声称「模块里每一个把 JSON 值交给 `Object::set()` 的入口，其最后一步都是 `coerce_to_property_type`，
  因此不可能存在『转换过了但槽位没判』的路径」。实际有两条**不经该闸门**的写路径：
  `editor_set_viewport_3d_camera`（`position`/`rotation_degrees` → `Vector3` 的 `real_t` 分量）与
  `editor_setup_world_environment`（`bg_color`/`ambient_color` → `Color` 的 `float` 分量）。
  两者把 `double` 直接 `(real_t)`/`Color(...)` 收窄，`1e300 → inf`、`3.5e38 → inf`，返回 `code=0`，
  且 `Color` 那条**已经落盘**。这是 M4b 判 fail 的 D-4 的同一形态，只是换了工具。
- **evidence（全部本次自行构造）**：
  - `editor_set_viewport_3d_camera{position:{x:1e300,y:0,z:0}}` → `code=0`，响应
    `{"fov":70.0100021362305,"position":{"x":1e99999,"y":0.0,"z":0.0},"rotation_degrees":{…}}`；
    独立通道 `editor_execute_gdscript`：`EditorInterface.get_editor_viewport_3d().get_camera_3d().global_position` =
    **`(inf, 0.0, 0.0)`**（`evidence/R2_pos_1e300.response.json`）。
  - `rotation_degrees:{x:3.5e38,y:0,z:0}` → `code=0`、`"x":1e99999`、独立读 `(inf, 0.0, 0.0)`。
  - `editor_setup_world_environment{bg_color:{r:1e300,g:0,b:0}}` → `code=0`（`setup:true`）；随后 `editor_save_scene`，
    `scenes/main.tscn` 内出现 **`background_color = Color(inf, 0, 0, 1)`**（`sub_resource type="Environment"`）。
  - **反向对照**：`bg_color:{r:0.1,g:0.2,b:0.3}` → 文件里 `background_color = Color(0.1, 0.2, 0.3, 1)`；
    `fov=1e300` 被引擎自己的范围校验丢弃并**如实回显** `70.01`（说明缺陷只在参数收窄处）。
- **location**：`tools/editor_write_scene_editor.cpp:149`（`_optional_vector3` 的 `(real_t)` 转换）、`:739`（`set_fov((real_t)fov)`）；
  `tools/editor_node_setup.cpp:128`（`Color(values[0], values[1], values[2])`）→ `:339/:345`（`set_bg_color`/`set_ambient_color`）。
  对照已修的 `tool_helpers.cpp:761-835`（`value_fits_slot`）与 `:1161-1175`（`coerce_to_property_type` 出口判定）。
- **recommendation**：把「任何 JSON 数值 → 任何 C++ 成员/分量」的收窄统一走 `value_fits_slot`：
  `_optional_vector3` 的每个分量、`fov`、`Color` 的每个分量在**写入前**判 `REAL_T`（`|x| > FLT_MAX` 或
  `x != 0 && (float)x == 0` → `-32602`，消息给出引擎会写的值）；并加一条**结构性护栏**——
  「凡出现 `(real_t)`/`(float)`/`Color(`/`Vector3(` 形式的数值收窄，必须能说出它经过了哪一次闸门调用」，
  或在 CI 里用 grep 清单把这些点钉住（本轮已枚举全部收窄点，见 §7 的 `unconfirmed` 之外无遗漏声明）。

### D-8（severity: **medium**，ergonomics / E-1）`project_get_scene_dependencies` 的 `type` 不是类型、`path` 不是路径

- **claim**：`type` 只在「无 `uid=` 的 ext_resource」上为空；一旦 `.tscn` 带 `uid=`（引擎自己保存的场景都带），
  `type` 会变成 **fallback 路径**（`res://main.gd`）；同时 `path` 是 `uid://…` 而不是 `res://`。
  模块注释自认在复刻迁移源 `add_types=false` 的口径，但引擎**一次调用**就能给出类型。
- **evidence**：`{"count":1,"dependencies":[{"path":"uid://c7mt5x5j361vt","type":"res://main.gd"}],"path":"res://scenes/main.tscn"}`（`E1_dep.response.json`）。
- **location**：`tools/project_read_analysis.cpp:728-742`（`get_dependencies(normalized, &dependency_paths)` 未传 `p_add_types`，
  再按 `parts[2]` 取「类型」）。
- **recommendation**：`get_dependencies(path, &deps, /*p_add_types=*/true)` 并把**最后一段**作为 fallback、`parts[1]` 作为类型
  （`resource_format_text.cpp:960-968` 的布局：有 uid 时 `path::type::fallback`，无 uid 时 `path::type`）；
  `path` 用 `ResourceUID::id_to_text/id_to_path` 归一成 `res://`（引擎的 `resource_uid.h`）。

### D-9（severity: **medium**，ergonomics / E-2 + E-8）编辑器侧路径口径是「编辑器内部绝对路径」

- **claim**：`editor_get_scene_tree` 是**唯一**产出路径的工具，却给出 `/root/@EditorNode@…@SubViewport@9998/Main/Actor`
  这种编辑器 UI 内部路径；错误消息（`-32001`）也回显同一串。同一模块的成功响应里 `node_path` 却是 `"Actor"`。
- **evidence**：E-2/E-8 两行（`E2_tree1.response.json`、`R2_badprop.response.json`）；两次运行（含重启编辑器）该串**逐字节相同**，
  故「每次运行都变」**未复现**，但它是编辑器布局的内部 id、不是契约标识（同一 fork 里 `unique_id=` 才是稳定标识）。
- **location**：`tools/editor_node_read.cpp`（scene tree 构造）+ `tools/running_game_node_write.cpp:494`（`node->get_path()` 拼错误路径）。
- **recommendation**：路径一律用 `Node::get_path_to(edited_root, /*p_use_unique_path=*/true)`（`node.h:573`）或
  `get_path_to(root)` 的相对形式；若要暴露稳定标识，用 `get_unique_scene_id()`（`node.cpp:2139`，已随场景保存）；
  错误消息里用相对路径 + 名字，而不是整条编辑器路径。

### D-10（severity: **medium**，ergonomics / E-3）同类值两种读回形状（对象 vs 字符串），且 packed 脚本默认值读回 `null`

- **claim**：`serialize_variant` 给 `Vector2/2i/3/3i/Color/Rect2` 专门分支，`Vector4` 与所有 packed 数组落到 `stringify()`
  → 字符串；消费者必须对「对象/字符串/null」分支。
- **evidence**：单次读回 `{"position":{…},"v2i":{…},"color":{…},"rect":{…},"v4":"(5.0, 6.0, 7.0, 8.0)","pv2":"[(1.0, 2.0)]","pv4":"[(1.0, 2.0, 3.0, 4.0)]"}`；
  另在**未写过的新场景**上：`{"bytes":null,"num":0.25,"pv2":null,"pv4":null,"v4":"(11.0, 12.0, 13.0, 14.0)"}`，独立 GDScript
  `str(r.pv2)` 同为 `<null>`（即 packed 的脚本导出默认值在编辑场景实例上就是 nil，**不是模块造成的**，但消费者同样吃这个形状）。
- **location**：`tools/tool_helpers.cpp:94-200`（`serialize_variant` 的 `default:` 分支）。
- **recommendation**：`Vector4`/`Rect2`/`Transform*`/packed 数组给显式分支（数组给 JSON 数组、Vector4 给 `{x,y,z,w}`），
  并写进契约；packed 默认值为 nil 的现象要在契约里注明（或读侧给 `[]` 而不是 `null`）。

### D-11（severity: **medium**，ergonomics / E-6）两个「日志读取」工具读的是共享文件、还是别的进程的日志

- **claim**：`editor_get_output_log` / `editor_get_errors` 只读 `user://logs/godot.log`（硬编码、无参数）：该文件在同工程内被编辑器/游戏进程**共享并轮转**，
  实测编辑器端点读到的是**游戏进程**的行；在轮转窗口里 `open()` 失败就直接 `-32603`（不是诚实空）。
  而「清面板」的 `editor_remove_output_log` 走的是进程内 `EditorLog`——一个能清、一个读不到，语义分裂。
- **evidence**：`-32603 "cannot open the log file 'user://logs/godot.log'"`（探测于 23:56:57，`godot.log` 的轮转文件 mtime 23:56:58，**晚 1 秒**）；
  文件存在后 `editor_get_output_log` → `lines=["[MCP] listening on 127.0.0.1:9889 (editor=false, tools=53)", …]`、`source="log_file"`；
  `main.cpp:2287` 默认 false。
- **location**：`tools/editor_read_scene_inspector.cpp:71`、`:94-119`、`:131-190`。
- **recommendation**：编辑器侧改用进程内来源（`EditorLog::get_message_count()`/`_rebuild_log`，
  `editor/editor_log.h:104`；或 `EditorNode` 的日志面板）并把 `source` 标注清楚；
  缺失时**诚实空**（`source:"no_log_file"`）+ 建议「用 `--log-file` 或打开 `debug/file_logging/enable_file_logging`」，
  而不是 `-32603`。

### D-12（severity: **low-medium**，ergonomics / E-9）`project_read_resource` 读资源却不给内容

- **claim**：只回 `{path,type,loaded}`，迫使调用方为「看资源里有什么」再走 `editor_execute_gdscript`（多一趟）。
- **evidence**：`{"loaded":true,"path":"res://cv_d5_b.tres","type":"Curve"}`；同资源引擎侧有 7 个 STORAGE 属性。
- **location**：`tools/project_write_resource_scene.cpp`（`project_read_resource` 的结果构造）。
- **recommendation**：加 `properties`（`get_property_list()` 过滤 `PROPERTY_USAGE_STORAGE`，
  值走 `serialize_variant`），或至少在 `type` 之外给 `property_names`。

### D-13（severity: **medium**，ergonomics / E-10）`editor_play_scene` 不转发 `--mcp-port`，且「模块内不可修」的结论**不成立**

- **claim**：模块注释（`tools/editor_playback.cpp:64-69`）称编辑器不会把 `--mcp-port` 转发给游戏子进程、**模块自己不改**。
  前半句实测正确（子进程 cmdline 无 `--mcp-port`），后半句在引擎源码面前不成立：
  `EditorRunBar::play_main_scene/play_current_scene/play_custom_scene` 都带公开的
  `const Vector<String> &p_play_args`（`editor_run_bar.h:123-125`），并且 `EditorNode::call_run_scene()` →
  `EditorPlugin::run_scene(scene, Vector<String>& args)` 是官方「启动前改写参数」的钩子
  （`editor_node.cpp:7797`、`editor_plugin.h:218`）。
- **evidence**：子进程 cmdline 全文（PID 47384）；同一子进程**监听 9891**（= scratch 工程 `godot_mcp/port`），
  证明端口来自工程设置——这正是要求调用方做的「多步舞蹈」（改工程设置 → 重启 → 再改回来）。
- **location**：`tools/editor_playback.cpp:107-152`（调用 `EditorInterface::play_*()`，无参数可用）。
- **recommendation**：`editor_play_scene` 增加可选 `port`（或默认把**本编辑器解析到的端口**转发），
  实现上走 `EditorRunBar::get_singleton()->play_*(…, args)`；若坚持只能靠工程设置，则把这条**写进 `description`**
  并返回 `data.port_source="project_setting"` + 需要的键名，让调用方不必靠读源码发现。

### D-14（severity: **medium**，ergonomics / G-1）不支持子属性路径

- **claim**：`editor_set_node_property` 把 `position:y`、`v4:x` 当作「不存在的属性」拒绝，
  而引擎有 `Object::set_indexed/get_indexed`（`object.h:697-698`，实现 `object.cpp:475-532`），
  编辑器 Inspector 正是用它来写 `material.albedo_color` 这类子属性。
- **evidence**：`v4:x` → `-32001`；`position:y` → `-32001`（消息含整条内部路径）。
- **recommendation**：属性名含 `:` 时走 `set_indexed`（并用同一收窄闸门判分量），或至少新增
  `editor_set_node_subproperty`，避免调用方为一次子属性修改写资源再赋回。

### D-15（severity: **medium**，latent，源码级）`REAL_T` 槽位在双精度构建下的放行是错的

- **claim**：`value_fits_slot(..., REAL_T, ...)` 在 `#ifdef REAL_T_IS_DOUBLE` 下**无条件 `return true`**
  （`tool_helpers.cpp:771-775`），但 **`Color` 的分量恒为 `float`**（`core/math/color.h:39-42`）、
  **`PackedFloat32Array` 的元素恒为 `float`**；两者在本模块里都被标成 `REAL_T`
  （`_container_element_slot`：`PACKED_FLOAT32_ARRAY → REAL_T`，`tool_helpers.cpp:850-851`；
  `Color` 分量 `COMPONENT_WIDTH_REAL`，`running_game_node_write.cpp:261-264`）。
  于是在 `precision=double` 构建下，`1e300` 会被判「存活槽位」，再被 `Color`/`PackedFloat32Array` 的
  `float` 拷贝成 `inf` —— 与 D-4 完全同源。
- **evidence**：源码（本轮单精度构建**不可观测**；`SConstruct:192` 默认 single，`--version` 亦为单精度）。
- **recommendation**：把 `REAL_T` 拆成 `REAL_T`（随构建）与 `FLOAT32`（恒 32 位），
  `Color` 分量与 `PackedFloat32Array` 元素用 `FLOAT32`；或让 `REAL_T` 分支在 double 构建下仍执行
  「按 float 判定」的等价检查。加一条 doctest 覆盖 `precision=double` 的配置无法在本环境跑，至少写成断言级注释并纳入风险。

### 不算缺陷但必须记录的两处「任务书前提与代码不符」

1. **E-7**：实现用 `node->set_script()`（`tools/editor_script_write.cpp:259`），不存在 `node.set("script", …)` 泛写。
2. **E-4/E-5**：两个 shader 工具属 **B5（未实现）**，M4 范围内**不可测**；迁移源的缺陷（`scene_3d.rs:131/142` 忽略 `material_slot`、硬编码槽 0）应作为 B5 的实现约束保留。

---

## 6. 观察（**未判为缺陷**，逐条给理由）

- **O-1 `str()` 对小于 1e-14 的值会显示 `0.0`**：`1e-30` 写入后回显 `"new_value":0.000000000000000000000000000001`（**值正确**），
  但独立通道 `editor_execute_gdscript` 的 `str(rotation)` 返回 `0.0` —— 原因是 `String::num` 默认 14 位定点（`core/string/ustring.cpp`）。
  **结论**：`str()` 只能当「是否 inf/nan」的探针，不能当小数的等值判据；判「读回旧值」时旧值选 0.5 这类可打印值是必要的。
- **O-2 `fov=1e300` 诚实**：引擎 `Camera3D::set_fov` 自带 1–179 校验 → 回显写后真值 `70.01`。**不是静默错值**。
- **O-3 `INT` 成员仍是 `WIDE`（声明边界）**：`Curve.bake_resolution=3000000000` → `ignored{requested,stored:100}`；
  `z_index=3000000000`（M4b）→ 回显写后真值。**诚实但“少了拒绝”**，属 `REPORT-022 §2.4` 已声明边界。
- **O-4 packed 脚本导出默认值在编辑场景实例上为 `nil`**（N13/R3：`pv2/pv4/bytes → null`，`v4/num` 正常）。
  独立 GDScript 同样看到 `<null>`，因此**不是模块的序列化问题**；根因在引擎/脚本默认值应用，未深挖（§7 `unconfirmed`）。
  对消费者的影响已并入 D-10。
- **O-5 `editor_get_errors` 与 `editor_get_output_log` 返回形状不一致**（前者无 `source` 字段）——并入 G-4。
- **O-6 我自己的 4 条 FAIL 全部是装置/期望错误**（见 §2.5 注、§9 附录 A.3），不计入产品缺陷。

---

## 7. `unconfirmed`（本轮未能独立证实/证伪，如实列出）

1. **E-2 的「每次运行都变」**：我做了「同进程两次」与「重启编辑器进程后再采集」两次对照，结果**逐字节相同**；
   因此**没有复现**该子断言。编辑器布局/插件变化时是否变化，本轮未构造。
2. **D-15（`REAL_T_IS_DOUBLE` 下的 `Color`/`PackedFloat32Array` 放行）**：源码级结论（`#ifdef` 分支 + `Color`/packed 的恒 `float` 声明），
   **未构造双精度二进制**验证（重建 `precision=double` 会替换被验二进制，且任务书要求门与证据都绑定同一 HEAD 二进制）。
3. **packed 导出默认值为 nil 的根因**：实测现象与独立 GDScript 一致，但未定位到引擎代码路径。
4. **G-3（`clear` 默认 `true` 删除共享桥接文件的并发危害）**：只做了单客户端语义验证，未构造多客户端交错。
5. **`editor_get_output_log` 首次 `-32603` 的确切触发条件**：两次观测分别是「探测落在 `godot.log` 轮转窗口 → `-32603`」
   与「文件存在（含游戏进程的行）→ `code=0`」；我只用 `user://logs` 的文件 mtime 做了 1 秒级的时序对齐，
   未穷举「文件存在但被另一进程持锁」的其它时序。
6. **窗式（非 headless）下的截图/视口分支**（M4b risk 6）：本轮仍未覆盖，与本轮范围无关，继续挂账。

---

## 8. `risks`

1. **D-7 说明「按工具名逐条修」还会继续漏**：`REPORT-022` 把闸门放进 `coerce_to_property_type`，
   就**只**覆盖了「走 `Object::set()` 的属性写」；凡是「先自己算好一个值、再调用专用 setter」的路径
   （视口相机、环境颜色、以及将来 B5 的 shader/material/粒子族）都会绕过它。
   建议把判据写成**结构性**的：「任何 `(real_t)`/`(float)`/`Color(`/`Vector3(` 数值收窄点，都必须显式经过一次槽位判定」，
   并用 grep 清单把它们钉进 CI（本轮已给出行号清单）。
2. **D-9/D-10 是「可链式喂回」的系统性问题**：四个产出型工具的返回都不能直接喂回别的工具
   （内部绝对路径 / `uid://` / 字符串形状 / 空内容），调用方被迫写解析与转换代码。§2.F 已把这条列为验收条款，
   下一轮应以「一棵调用链跑通、零字符串手术」为验收方式。
3. **D-11 的日志工具默认不可用**：任何依赖 `editor_get_errors` 判断「有没有报错」的自动化，在默认配置下会拿到 `-32603`
   或**别的进程**的日志 → 可能得出相反的结论。
4. **D-13 的端口舞蹈**：若不修，任何「跑起来用 MCP 观察」的自动化都得改工程设置，等于把测试代码写进被测工程。
5. **D-15 是同一类缺陷的第 4 次形态变更**（容器元素 → 分量 → 标量 → 构建配置），说明「按形状补丁」的方法论持续失效。
6. **状态残留**：本轮 scratch 工程在 `editor_setup_world_environment` 之后保存过一个含 `Color(inf,0,0,1)` 的场景
   （`%TEMP%\audit-m4c\project\scenes\main.tscn`，sha `…`）。它只是证据，不在仓库内；但提醒后续验收者：
   **一旦在真实工程里跑过这类工具，`inf` 会随保存进入工程文件**。

---

## 9. `verdict`

| 分类 | verdict | 依据 |
|---|---|---|
| **全量对等**（含 scope） | **pass** | 我自己的 `tools/list` 抓包：union 113 == manifest `implemented`；9888 = 91、9889 = 53 == 按 `scope` 对称推导；两向差集空；`description`+`inputSchema`+键集**逐字 0 差异**；重复名 0；跨端点 `-32601` 且不执行 |
| **诚实性** | **fail** | D-4 的 5 条写路径**全部真闭合**（6 反例 × 5 路径 × 4 证据形态），D-5/D-6 **真闭合**，4 个已修 fix-first **真的做到**，3 个 B5 fix-first + 2 个 `unregister` 确未注册；**但 `REPORT-022` 的「统一闸门覆盖全部写路径 / 同类面清零」断言被 D-7（high）反证**：`editor_set_viewport_3d_camera` 与 `editor_setup_world_environment` 仍 `code=0` 静默写 `inf`（回显 `1e99999`、`Color(inf,0,0,1)` 已落盘）。另有 D-15（latent medium） |
| **行为一致**（对抗性抽样） | **pass** | 抽样 25+ 工具（M4b）在本轮由「4 个 fix-first 复验 + 跨端点 + 事务 + 延迟通道」复核，未发现新的行为/宣称不一致；D-7 归入诚实性，Ergonomics 归入 §2.F 类 |
| **安全与事务** | **pass** | 路径 3 的批量拒绝**未挂载任何节点**（场景树无 `D4Node*`）、路径 2「写前整体拒绝」、路径 5「Nothing was written」且 `good.tscn` sha 不变；跨端点 `-32601`；未观察到「报成功但只做一半」 |
| **延迟通道** | **pass** | 超时 1036 ms → `-32000`；两次 pending 不串线；pending 后常规请求 26 ms；端点继续服务 |
| **工程门** | **pass** | 版本 == HEAD（重建后）；模块 doctest **190/190 · 7716**；全引擎 **1616/1616 · 431998**；`accept_m1` **22/22 ×2、PASS 清单逐行相同**；`check_tool_groups` 四项 exit 0 |
| **端口纪律** | **pass** | 9877 全程 **36392**；仅用 9888/9889（+ 子进程按工程设置用 9891，已收）；收尾无监听、无孤儿；未改被跟踪文件、无 git 写操作 |
| **顺手性（GDR-23 / §2.F）** | **fail** | E-1（类型/路径都错）、E-2+E-8（编辑器内部绝对路径）、E-3（形状分裂）、E-6（读别的进程的日志/默认打不开）、E-9（读资源不给内容）、E-10（结论「模块内不可修」被引擎 API 反证）；E-4/E-5 = N/A（B5 未实现）、E-7 前提不成立；另自找 G-1/G-2/G-3/G-4 |

### 总 verdict：**`fail`**

**本轮的核心结论**：

1. **D-4 的 5 条写路径真的闭合了**：同样的 6 个反例 × 5 条路径 × 四条证据形态（`-32602` / 拒绝响应无值回显 /
   显式保存后 `.tscn` 无 `inf`/`nan` 且 sha 相同 / 另一读工具读到旧值）全部成立，合法值与 `3.4e38` 边界正常写入；
   `project_create_resource` / `editor_setup_collision_shape` 等额外写路径也受同一闸门。
2. **D-5（回读/`ignored`）与 D-6（跨进程报告 + 三种诚实空）真的闭合**，且我用独立 GDScript 与文件内容交叉验证过。
3. **但「统一闸门覆盖全部写路径」不成立 → D-7（high）**：`editor_set_viewport_3d_camera` 与
   `editor_setup_world_environment` 仍能把 `1e300` 静默写成 `inf` 并报 `code=0`（回显 `1e99999`，
   `Color(inf,0,0,1)` 已进入保存的场景）。这与 M4b 判 fail 的形态**完全同类同形**，必须回到阶段四修。
4. **顺手性（GDR-23）首轮审计判 fail**：六项确认缺陷、两项前提不成立/N-A、另有自找四项；
   其中 E-10 的「模块内不可修」结论被 `EditorRunBar::play_*(…, p_play_args)` 与
   `EditorPlugin::run_scene(scene, args)` 两处引擎证据直接反证。

---

## 10. `next_step_recommendation`

1. **优先修 D-7**：`_optional_vector3` 的每个分量、`set_fov` 的 `fov`、`_color_from_json` 的每个分量，
   全部在**写入前**走 `MCPTools::value_fits_slot(..., REAL_T, ...)`（沿用同一消息形状）；
   验收必须用**新形态**：① 响应回显值**有限**；② 保存后的 `.tscn` 里既没有 `inf`/`nan`，也没有
   `Color(inf…`；③ 独立 GDScript 读到旧值；④ 合法值仍写入（`Color(0.1,0.2,0.3,1)` 这类正向对照）。
2. **把 D-15 一并修掉**：拆 `FLOAT32` 与 `REAL_T` 两个槽位；`Color` 分量与 `PackedFloat32Array` 元素用 `FLOAT32`。
3. **加结构性护栏**：对 `(real_t)`/`(float)`/`Color(`/`Vector3(`/`Vector2(` 的收窄点做清单化检查（本轮已给行号），
   任一新增收窄点必须显式标注它经过的闸门，否则评审不通过。
4. **顺手性按 §2.F 判据成组修（建议顺序）**：
   E-1（`p_add_types` + `ResourceUID` 归一）→ E-3（显式序列化分支）→ E-9（`properties`）→
   E-6（改用进程内 `EditorLog`，缺失时诚实空）→ E-2/E-8（`get_path_to(root, use_unique_path)`）→
   E-10（转发 `--mcp-port` 或把 `port_source` 写进契约）→ G-1（`set_indexed` 子属性）→ G-2。
5. **回归范围**：修完必须重跑本报告的 §2.2 矩阵（脚本一条命令可复现）、D-5/D-6 段、
   D-7 的四个对象（camera.position / camera.rotation / worldenv.bg_color / worldenv.ambient_color），
   以及门③~⑤（`build_local.cmd -Force`；`tests/*.h` 变动时必须带 `-Force`）。
6. **文档**：把「槽位判定必须覆盖**不经 `Object::set()` 的专用 setter 路径**」写进 `DESIGN-DETAIL.md` 的写值闸门小节；
   把 E-1/E-3/E-6/E-9/E-10 的「引擎正解 API + 行号」写进 `PLAYBOOK` 的相关小节，作为 B5 的既定约束。
7. **验收方式建议**：§2.F 的顺手性条款最好用「**一条链零字符串手术**」的可执行验收（例如：
   `project_get_scene_dependencies → project_read_resource → editor_set_node_property(子属性) → editor_get_scene_tree`
   四个返回互相直接可用），而不是逐工具读码判断。

---

## 附录 A：证据与复现

### A.1 harness（本次自建，未复用任何既往脚本）

`%TEMP%\audit-m4c\`：`common.ps1`（`curl.exe -s -o` + sha256 + `ConvertTo-Json -Depth 32` 请求体 + 端口/进程树 + launcher）、
`run.ps1`（D-4 矩阵 / D-5 / D-6 / 新面 / 顺手性探针 / E-10 子进程 cmdline / E-2 重启对照）、
`run2.ps1`（绝对路径可喂回性 / 错误消息形状 / 写后形状 / **viewport camera 新面** / worldenv / 子属性路径）、
`run3.ps1`（日志工具二探 / worldenv 正向对照 / 默认值形状 / 碰撞形状闸门）、`run4.ps1`（B 段复验 + 延迟通道 + 跨端点）、
`gates.ps1`（门③④⑤ + tool-groups）、`analyze_equality.py`（解析后字段的集合/逐字/scope 对称）、`equality.txt`。

- 证据体：`evidence\*.request.json` / `*.response.json`（每个请求与响应原样落盘，含 sha256 与字节数，见各 `run*.log`）。
- 结果集：`results.json`（182 checks / 1 FAIL=我方装置错误）、`results2.json`、`results3.json`、`results4.json`。
- 门输出：`gate3.txt`、`gate4.txt`、`gate_groups.txt`、`accept1.txt`、`accept2.txt`、`gates_version.txt`、`gate_ports.txt`。
- 构建：`%TEMP%\mcp_server_build_local.log`（`FORCE` 删了两个陈旧 test obj；`EXIT_CODE=0`；未抑制 scons 输出）。

### A.2 关键命令

```powershell
cd F:\RustProjects\godot-mcp-pro\code\godot
cmd /c "modules\mcp_server\scripts\build_local.cmd -Force"     # tests=yes
.\bin\godot.windows.editor.x86_64.console.exe --version        # 4.8.dev.custom_build.50aadecca == HEAD 50aadecca9
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\audit-m4c\run.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\audit-m4c\run2.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\audit-m4c\run3.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\audit-m4c\run4.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\audit-m4c\gates.ps1"
python "$env:TEMP\audit-m4c\analyze_equality.py"
```

### A.3 四条 FAIL 记录的定性（全部为验收方装置/期望错误，非产品缺陷）

| FAIL | 原因 | 产品实际行为 |
|---|---|---|
| `C_game_assertions_ran` | 我的路径 4 合法对照把游戏侧 `rotation` 留在 `3.4e38`，「应通过」的断言也失败 | 报告正确记 `total=2, failed=2`；桥接/诚实空/clear 全部 PASS |
| `R2_abs_path_not_usable` | 我预期绝对路径不可喂回 | 实测**可以**（`code=0`）：模块接受两种形式 → E-2 收窄为「格式/口径」问题，见 D-9 |
| `R3_worldenv_control_ok` | 我的 GDScript 写了 `bg_color`（`Environment` 的正确属性名是 `background_color`）→ 求值返回 nil | 文件里 `background_color = Color(0.1, 0.2, 0.3, 1)`（正向对照成立） |
| `R4_auto_dismiss_honest` | 我要求响应文本不含 `auto_dismiss`，但消息里含工具名 `editor_set_auto_dismiss_dialogs` | 行为正确：`-32602`（类型错）/ `-32000 Not implemented`、`result` null、无字段回显 |

### A.4 临时文件与工作树

- 全部临时产物在 `%TEMP%\audit-m4c\`；scratch 工程在 `%TEMP%\audit-m4c\project\`。
- **未修改任何仓库被跟踪文件**（含测试文件，故无「还原留证」事项）；**未执行任何 git 写操作**；未安装依赖。
- 本报告是本次唯一新增的仓库文件：`modules/mcp_server/docs/reports/REPORT-AUDIT-M4c.md`。
