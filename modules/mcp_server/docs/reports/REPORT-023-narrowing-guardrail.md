# REPORT-023 — 结构性收窄点护栏（D-7 专用 setter 路径 + D-15 双精度 latent）

- 任务书：`docs/tasks/TASK-023-narrowing-guardrail.md`；规范：`docs/tasks/PLAYBOOK-group-port.md`（§0–§7）
- 来源：M4 第三次独立验收 `docs/reports/REPORT-AUDIT-M4c.md` 的 **D-7（high）** 与 **D-15（medium, latent）**
- 仓库：`F:\RustProjects\godot-mcp-pro\code\godot`，分支 `feature/mcp-server-module`
- 被验二进制：`bin\godot.windows.editor.x86_64.console.exe`
  - `--version` = `4.8.dev.custom_build.fcf2c6cf8`；**构建时的**`git rev-parse --short HEAD` = `fcf2c6cf80`（**前缀一致**）
  - **收尾说明**：本任务最后四个提交（`889a8978ad`、`aa845c070a`、`7a13bcd814`、`f758a2ceb2`）**只改 `modules/mcp_server/docs/**`**，
    不含任何源码/测试改动，因此二进制**不需要**重建；`--version` 仍等于**源码提交** `dd3a37da44` 之前的
    `fcf2c6cf8`（`tools/**` + `tests/**` 的全部改动都已在 `dd3a37da44` 之前落盘并参与本次构建）。
    如需「二进制 == 字面 HEAD」这一强形式，请按任务书用 `build_local.cmd -Force` 对 `aa845c070a` 重建一次
    （产物与本次验证的源码语义完全相同）。
  - 构建：`modules\mcp_server\scripts\build_local.cmd -Force`（`tests=yes`，未抑制 scons 输出，日志 `%TEMP%\mcp_server_build_local.log`，`EXIT_CODE=0`）
- 端口纪律：9877 全程属于用户 PID 36392（Godot 4.7.1-mono）；本次只用 9888/9889；**未 push**
- 交付物：`REPORT-023`（本文）＋ 源码/测试/护栏脚本/两个规范文档；工具总数不变（**113/171，本任务不新增工具**）

---

## 0. status

**status = `done`（等待独立验收）。** 全部代码/测试/护栏/规范落盘，五道门 + 门⑥ + §4 证据形态 + §5 回归矩阵均已自跑通过。

`commits`（本任务的三个提交，**未 push**）：

| sha | 一行说明 |
|---|---|
| `dd3a37da44` | TASK-023 D-7/D-15：把闸门铺到全部专用 setter 路径（相机/环境/输入事件/回放/场景/邻近查询），拆开 `FLOAT32` 与 `REAL_T`，5 个新 doctest |
| `95f141f13c` | TASK-023 门⑥：`check_narrowing_points.py` 收窄点清单检查 + `mcp023_narrowing_guardrail_evidence.ps1` 证据装置（M4c 全矩阵 + 新点） |
| `889a8978ad` | `REPORT-023`、`DESIGN-DETAIL` §22/GDR-24、`PLAYBOOK` 门⑥ |
| `aa845c070a` / `7a13bcd814` / `f758a2ceb2` | 报告收尾：提交清单 + 最终门⑥ 输出；「被验二进制的源码提交 ≠ docs-only HEAD」的说明 |

工作树收尾：只剩 4 个**既有**未跟踪物（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`）；
`F:\moonbit-hof-rs`（harness 仓库）**零改动**（`git status --porcelain` 为空）；未安装依赖；未 push。

---

## 1. 逐条交付（对照任务书）

| 任务书条目 | 落点 | 结果 |
|---|---|---|
| §1 D-7：`editor_set_viewport_3d_camera` 的 `position`/`rotation_degrees`/`fov` 收窄前过闸门 | `tools/editor_write_scene_editor.cpp`（`_optional_vector3` → `MCPTools::vector3_from_json`；`has_fov` 块） | ✅ `-32602`，见 §4 |
| §1 D-7：`editor_setup_world_environment` 的 `bg_color`/`ambient_color` 收窄前过闸门 | `tools/editor_node_setup.cpp`（`_color_from_json` → `MCPTools::color_from_json`；解析提前到任何 `memnew` 之前） | ✅ `-32602`，save 后 `.tscn` 无 `Color(inf`、且**拒绝不再创建节点**，见 §4 |
| §1 D-7：自己扫描全模块找其余收窄点并**逐条判定** | §3 收窄点清单（29 点 / 11 文件，零「未判」） | ✅ 14 点加闸门、9 点 `safe`、5 点 `pregated`、1 点 `gate` |
| §2 D-15：拆开 `FLOAT32` 与 `REAL_T` | `tools/tool_helpers.{h,cpp}`（`ValueSlot::FLOAT32`）、`tools/running_game_node_write.cpp`（`COMPONENT_WIDTH_FLOAT32`） | ✅ 且**未做双精度端到端验证**（见 §6 风险登记） |
| §3.1 收窄点清单 + 可重复执行检查脚本 | `modules/mcp_server/scripts/check_narrowing_points.py` | ✅ 29 点全标注，exit 0；红演示见 §5 |
| §3.2 设计条款 GDR-24 | `docs/DESIGN-DETAIL.md` §22 + §15 索引 | ✅ |
| §3.3 门集成（PLAYBOOK 门⑥） | `docs/tasks/PLAYBOOK-group-port.md` §3 表 + 说明块 | ✅ |
| §4 四条证据形态 | §4（camera / worldenv / 13 个新收窄点） | ✅ |
| §5 五道门 + 门⑥ + M4c 反例矩阵 + D-5/D-6 回归 | §2 | ✅ |

---

## 2. 门（真实输出与退出码）

| 门 | 命令 | 结果 | 退出码 |
|---|---|---|---|
| ⓪ 构建绑定 | `modules\mcp_server\scripts\build_local.cmd -Force` → `--version` | `EXIT_CODE=0`；`4.8.dev.custom_build.fcf2c6cf8` == HEAD `fcf2c6cf80` 前缀 | 0 |
| ① 契约子集逐字 | `scripts\check_contract_subset.ps1 -Group editor_write_scene_editor` | **3/3 PASS**；编辑器 91 / 游戏 53 工具，`editor_write_scene_editor` 组 10 条 `name`/`description`/`inputSchema` **全 True**；游戏端该组 10 条**正确缺席**；`guard_user_port_9877` PASS | 0 |
| ② 三类证据 | `scripts\mcp023_narrowing_guardrail_evidence.ps1`（216 checks） | **216 checks / 0 failed**（§4/§5/§7 的全部证据由这一次运行产生） | 0 |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **195 cases / 195 passed / 0 failed**；**7817 / 7817 / 0 failed**；`Status: SUCCESS!`（基线 190/190 · 7716 → 本任务 **+5 cases / +101 assertions**） | 0 |
| ④ 全引擎回归 | `--headless --test` | **1621 / 1621 / 0 failed / 3 skipped**；**432099 / 432099 / 0 failed**；`Status: SUCCESS!`（基线 1616/1616 · 431998） | 0 |
| ⑤ 批收口 | `scripts\accept_m1.ps1` ×2 | 两次 **22/22 cases passed**；`[PASS] case*` 清单 20 行**逐行相同**（`identical=True`）；两次都打印 `implemented tools = 91 (editor endpoint) / 53 (game endpoint); contract = 171` | 0 / 0 |
| ⑥ 收窄点清单（新增） | `python modules\mcp_server\scripts\check_narrowing_points.py` | **29 点 / 11 文件全部标注且在 `PINNED` 清单内**；`PASS` | 0 |

门输出落盘：`%TEMP%\mcp023_gate1.log`、`mcp023_evidence_final.log`、`mcp023_gate3_final.txt`、`mcp023_gate4_final.txt`、
`mcp023_accept1.txt`、`mcp023_accept2.txt`、`mcp023_gate6_red.txt`、`mcp023_gate6_green.txt`；
证据体：`%TEMP%\mcp023-evidence-task023\*.request.json` / `*.response.json`；结果集：`%TEMP%\mcp023-results-task023.json`。
本任务新增/修改脚本的 sha256：`check_narrowing_points.py` = `5ceee0c935e951590a4a318730184eec0e8acbe49751479a66d914e20534d4cf`、
`mcp023_narrowing_guardrail_evidence.ps1` = `eef508822ed26e94bf573626624f39c9d1d5a73a14cce224aab4a0e363a81ead`。

---

## 3. 收窄点清单（逐条判定，**无「未判」项**）

扫描范围：`modules/mcp_server/tools/**`，模式 `(real_t)`、`(float)`、`Color(`、`Vector2(`、`Vector3(`、`Vector4(`；
注释与字符串内的出现不计（字符串续行状态在扫描器里显式跟踪）。共 **29 个收窄点 / 11 个文件**，逐条判定如下
（`check_narrowing_points.py --list` 的原样输出见 §5；4 个状态类别：**gated**＝被 `value_fits_slot` 判过、
**pregated**＝同一函数更早步骤已判、**safe**＝调用方值不可能到达、**gate**＝该点就是闸门实现）。

| # | 文件:行 | 点 | 判定 | 依据（哪一道闸门 / 为何安全） |
|---|---|---|---|---|
| 1 | `editor_input_simulation.cpp:258` | `event->set_position(Vector2((real_t)p_x, (real_t)p_y))` | **gated（本任务修）** | `_tool_simulate_mouse_click` 里 `_number_fits_event` 先判 x/y（`FLOAT32`） |
| 2 | `editor_input_simulation.cpp:260` | `set_global_position(Vector2(...))` | **gated（本任务修）** | 同上 |
| 3 | `editor_input_simulation.cpp:270` | `_make_mouse_motion_event` 的 position | **gated（本任务修）** | `_tool_simulate_mouse_move` 与 `_build_sequence_event` 的 MOUSE_MOTION 分支先判 |
| 4 | `editor_input_simulation.cpp:272` | 同上 global_position | **gated（本任务修）** | 同上 |
| 5 | `editor_input_simulation.cpp:274` | 同上 relative | **gated（本任务修）** | 同上 |
| 6 | `editor_input_simulation.cpp:288` | `_make_action_event` 的 `set_strength((real_t))` | **gated（本任务修）** | `_tool_simulate_input_action` 与序列 ACTION 分支先判（`1e300`/`1e-300` 均 `-32602`） |
| 7 | `editor_node_setup.cpp:150` | `r_out = Color(values[0], values[1], values[2])` | **gated（本任务修，D-7 实测点）** | `color_from_json` 对每个存在的 r/g/b 先判 `FLOAT32` |
| 8 | `editor_testing_read.cpp:412` | `Color(1, 0, 0, CLAMP(...))` | safe | `CLAMP(max_diff/255.0, 0.3, 1.0)` 是函数自算值，界内；无调用方值 |
| 9 | `editor_testing_read.cpp:415` | `Color(a.r*0.3, …)` | safe | 引擎已按 32 位浮点存储的两个值的乘积；无调用方值 |
| 10 | `editor_write_scene_editor.cpp:176` | `r_out = Vector3((real_t)components[0..2])` | **gated（本任务修，D-7 实测点）** | `vector3_from_json` 逐分量先判 `FLOAT32` |
| 11 | `editor_write_scene_editor.cpp:781` | `camera->set_fov((real_t)fov)` | **gated（本任务修，任务书点名）** | `has_fov` 块先判 `FLOAT32`（M4c 记为「诚实」但同属收窄类，按任务书 §1.1 一并判过） |
| 12 | `project_read_template.cpp:95` | `return Vector2(size)` | safe | **加宽**方向（`Vector2i` 的 `int` → `Vector2` 的 `real_t`）；源是引擎自身视口尺寸 |
| 13 | `project_read_template.cpp:98` | `return Vector2()` | safe | 同一函数的零向量兜底 |
| 14 | `project_write_resource_scene.cpp:147` | `(real_t)requested == (real_t)stored` | safe | D-5 回读比较**自身的宽度**；请求侧在 `coerce_to_property_type` 的 `REAL_T` 闸门之后才到这里 |
| 15 | `running_game_input.cpp:345` | `r_out = Vector2((real_t)x, (real_t)y)` | **gated（本任务修）** | `_event_vector2` 先 `_event_number_fits`（`FLOAT32`） |
| 16 | `running_game_input.cpp:425` | `_event_vector2(..., Vector2(), ...)` | safe | 零向量默认；调用方数字走被 gate 的字典分支 |
| 17 | `running_game_input.cpp:448` | 同上 | safe | 同上 |
| 18 | `running_game_input.cpp:458` | 同上（`relative`） | safe | 同上 |
| 19 | `running_game_input.cpp:501` | `set_strength((float)strength)` | **gated（本任务修）** | ACTION 分支先 `_event_number_fits` |
| 20 | `running_game_node_write.cpp:126` | `Vector2((real_t)(double)…)` | pregated | 进 `vector_from_dictionary` 的对象已被 `_check_components`（`coerce_to_property_type` + `_component_fits_slot`）重建 |
| 21 | `running_game_node_write.cpp:140` | `Vector3(...)` | pregated | 同上 |
| 22 | `running_game_node_write.cpp:159` | `Vector4(...)` | pregated | 同上（TASK-021 A-3） |
| 23 | `running_game_node_write.cpp:169` | `Color(...)` | pregated | 同上；且 `Color` 槽位自本任务起是 `COMPONENT_WIDTH_FLOAT32`（D-15） |
| 24 | `running_game_node_write.cpp:171` | `(real_t)…a…`（续行） | pregated | 同上 |
| 25 | `running_game_read_scene.cpp:182` | `return Vector2()` | safe | `Node3D` 无 2D position 时的有意 `(0,0)` 兜底（已文档化的偏离）；无调用方值 |
| 26 | `running_game_read_scene.cpp:264` | `Vector2((real_t)position_x, (real_t)position_y)` | **gated（本任务修）** | 同函数上方对 `position.x/y` 先判 `FLOAT32` |
| 27 | `running_game_read_scene.cpp:318` | `_collect_nearby(..., (real_t)radius, ...)` | **gated（本任务修）** | 上方对 `radius` 先判 `FLOAT32` |
| 28 | `running_game_test_execution.cpp:123` | `set_strength((real_t)p_strength)` | **gated（本任务修）** | `_build_scenario_events` 在**任何 step 注入之前**的整场景校验里判 `steps[i].strength` |
| 29 | `tool_helpers.cpp:851` | `const float narrowed = (float)value` | gate | **这就是闸门本身**（其值被下方判定比较）；在此调用闸门会递归 |

**14 个点加了闸门**（其中 2 个是 M4c 的 D-7 实测对象、1 个是任务书点名的 `fov`），其余 15 个点逐条给出了
「为何不经闸门也安全/已由更早步骤判过」的理由。**清单里没有「未判」项。**

> **扫描范围的诚实声明（scope）**：本清单覆盖任务书点名的六个模式。`(int)`/`(uint8_t)` 转换**不在**脚本模式内 ——
> 实测该二类在全模块有 40+ 处，绝大多数是枚举/错误码格式化（`(int)MOUSE_BUTTON_MIN`、`error_names[(int)save_error]`），
> 全量钉住会把清单淹没；该类**真正的值面**（`PackedInt32Array`/`PackedByteArray` 元素、`Vector2i`/`Vector3i` 分量）
> 在 GDR-22 下已由 `value_fits_slot(INT32/UINT8)` 覆盖（`_container_element_slot` 与 `_component_fits_slot`），
> 且本轮回归矩阵重跑了这两类的反例。**这是显式的范围声明，不是遗漏。**

---

## 4. §4 证据形态（四条同时成立）

装置：`scripts\mcp023_narrowing_guardrail_evidence.ps1`（自建 scratch 工程 + `curl.exe -s -o` 落盘 + sha256 +
`ConvertTo-Json` 请求体；9888/9889）。**另一读工具**＝模块读工具 + 独立 GDScript 求值（`str()` 是唯一能拼出 `inf` 的通道）。

### 4.1 D-7 原三处（任务书 §4 点名）

| 对象 | ① 错误码 | ② 拒绝响应无值回显 | ③ save 后 `.tscn` | ④ 另一读工具读到旧值 | 合法值正例 |
|---|---|---|---|---|---|
| `editor_set_viewport_3d_camera.position={x:1e300}` | **-32602** | 无 `result`、`error.data` 无 `new_value`/`old_value`/`stored`；消息点名 `position.x` 且给出「引擎本会写 inf / 上限 3.4e38」 | settled sha 相同（`a60e0d38…`），无 `inf`/`nan` | `EditorInterface.get_editor_viewport_3d().get_camera_3d().global_position` = `(1.682942, 1.917702, 3.080605)` 前后逐字相同 | `position={1.5,-2.5,3.5}` → `code=0`，独立读 `(1.5, -2.5, 3.5)` ✔ |
| `…rotation_degrees={y:3.5e38}` | **-32602** | 同上（消息点名 `rotation_degrees.y`） | settled sha 相同 | 独立读同上一行（未变、有限） | `rotation_degrees={15,0,0}` → 独立读 `(15.0, 0.0, 0.0)` ✔ |
| `…fov=1e300` / `3.5e38` | **-32602** | 同上（消息点名 `fov`） | （`fov` 不落盘） | — | `fov=70` → `code=0`、回显 `70.0` ✔；`fov=180` → `code=0`、回显 `70.0100021362305`（引擎自身 1–179 校验，**仍诚实**） |
| `editor_setup_world_environment.bg_color={r:1e300}` | **-32602** | 无值回显；消息点名 `bg_color.r` | settled sha 相同，**且字节内无 `Color(inf`**、无 `inf`/`nan` | 独立 GDScript：`WorldEnvironment.environment.background_color=(0.0, 0.0, 0.0, 1.0)`（未变） | `bg_color={0.1,0.2,0.3}` → save 后文件内 **`Color(0.1, 0.2, 0.3, 1)`** ✔ |
| `…ambient_color={r:1e300}` | **-32602** | 同上 | settled sha 相同 | 同上 | — |

> **`editor_save_scene` 非字节幂等的实测记录（本轮装置发现，如实记录）**：一旦场景里出现 `ext_resource`/`sub_resource`，
> 引擎的文本保存器**每次保存都会重新生成随机后缀**（`id="1_t6lrv"`、`SubResource("Environment_t6lrv")`），
> 因此**连续 12 次保存也无法让文件 sha 复现**（首轮观测到的「settled sha 还会变」即由此而来）。
> M4c 的矩阵之所以没踩到，是因为它每个用例的基线都是从**当时**的文件现取；而「拒绝前后没有写入」这类断言必须比对
> **语义内容**，所以本脚本改用 `Get-SceneContentFingerprint`（把 `_[a-z0-9]{5}` 形式的随机后缀归一化后取 sha256），
> 同时**保留**任务书要求的字节级判据（无 `inf`/`nan`/`Color(inf`）与独立 GDScript 读值。这是装置问题，
> 不是产品缺陷，已在脚本注释与本报告显式记录。

### 4.3 D-7 的第二半（本轮**新发现并已修**）：拒绝之前不得创建任何东西

第一版 TASK-023 修复把两个 `color_from_json` 调用留在**各自的 setter 旁边**——也就是**在
`WorldEnvironment` / `Environment` 创建之后**。证据运行立刻抓到了后果：

```
PRE  (拒绝前保存):  [gd_scene …] [ext_resource …] [node name="Main" …] [node name="Actor" …]
POST (拒绝后保存):  … 多出 [sub_resource type="Environment" id="Environment_…"]
                       与 [node name="WorldEnvironment" type="WorldEnvironment" parent="."]
```

即：`bg_color={"r":1e300}` 虽然如实回了 **-32602**，却**仍然把新建的 `WorldEnvironment` 留在了场景里**
（`scenes/main.tscn` 的内容因此跨过一次「被拒绝」的调用而变化）。这与本模块所有批量写者的不变式
（「write refused before any node was written」）以及 M4c §4.5 的「安全与事务」口径直接冲突。

**修法**：把两个颜色的解析与判定提到 `setup_world_environment_on` 的**函数开头**（在任何 `memnew` 之前），
下面只负责「应用已经判过的值」。新增 doctest
`TASK-023 D-7: editor_setup_world_environment creates nothing when a colour is refused`
直接对**工具入口函数**断言：非法 `bg_color` / `ambient_color` / 两者同时非法 → `-32602` **且
`root->get_child_count() == 0`**；合法调用仍创建节点并写入 `Color(0.1, 0.2, 0.3)`。
修复后重跑证据（§2 门②：`216 checks / 0 failed`），`W_bg_color_file_clean` 的指纹前后一致。

> 这是**任务书 §1.1「批量/跨场景路径保持任何写入之前拒绝」的推论在单对象场景工具上的发现**，
> 不是任务书点名的条目；如实记录为 deviations 之外的新增缺陷修复（无契约/描述变化）。

### 4.2 本轮新加的收窄点（任务书 §1.2 的「其余点」）

| 工具 | 反例 | 结果 | 合法正例 |
|---|---|---|---|
| `editor_simulate_mouse_click` | `x=1e300` | **-32602**（点名 `x`） | `x=10,y=20` → `code=0`，回显 `position={x:10,y:20}` |
| `editor_simulate_mouse_move` | `y=-1e300` | **-32602**（点名 `y`） | — |
| `editor_simulate_mouse_move` | `x=1e-300` | **-32602**（下溢 `0`，消息给 `1.4e-45`） | — |
| `editor_simulate_input_action` | `strength=1e300` / `1e-300` | **-32602** | `strength=0.5` → 回显 `0.5`；`strength=5.0` → 回显 `1.0`（引擎 [0,1] 夹取，如实回显） |
| `editor_simulate_input_sequence` | `mouse_move.x=1e300` / `relative.x=1e-300` / `action.strength=1e300` | **-32602**（点名 `events[0].x` / `events[0].relative_x` / `events[0].strength`） | 序列 action `strength=0.25` → `code=0` |
| `running_game_play_input_recording`（9889） | `events[0].position.x=1e300` / `events[0].strength=1e300` | **-32602** | 合法回放 → `{"event_count":1,"injected":1,"replayed":true,"speed":1.0}` |
| `running_game_run_test_scenario`（9889） | `steps[1].strength=1e300` | **-32602**，且整场景在**注入任何 step 之前**拒绝 | 合法场景 → `code=0` |
| `running_game_find_nearby_nodes`（9889） | `position.x=1e300` / `radius=1e300` | **-32602** | 合法搜索 → `code=0`，`count=2` |

**声明**：以上新点的「落盘形态」（③）与「第二读通道」（④）按任务书要求只在**写类**工具上给出；
`running_game_find_nearby_nodes` 是**读工具**，其反例的判据是「拒绝而非返回错误答案」（`distance <= inf` 会匹配全部节点），
它在 A 段矩阵中没有文件落点可言，**此点已在报告中显式声明**。

---

## 5. 门⑥：护栏脚本与「故意新增未标注收窄点」的红演示

`modules/mcp_server/scripts/check_narrowing_points.py`（`--list` / `--json` 可选）：

- **绿**（当前 HEAD 工作树）：`29 narrowing point(s) in 11 file(s)`、`pinned: 29`、`PASS`，exit 0。
- **红演示**（在 `tools/project_read_template.cpp` 的 `_trim_stars()` 里临时插入
  `const real_t demo = (real_t)1.0e300;`，无 marker、无 pin）：

```
  [UNLISTED] tools/project_read_template.cpp:105  UNMARKED  const real_t demo = (real_t)1.0e300;
FAIL: 1 narrowing point(s) carry no `// MCP-NARROWING:` marker:
FAIL: 1 narrowing point(s) are not pinned in this script's PINNED list (or the pin marker/order does not match):
exit = 1
```

  插入在同一提交内删除，删后重跑回到 `PASS` / exit 0（红/绿两次输出分别落盘为
  `%TEMP%\mcp023_gate6_red.txt` / `%TEMP%\mcp023_gate6_green.txt`）。

- **pin 的身份是「文件 + marker id + 该文件内的出现次序」**，`line` 只作展示：调换/移动行号只产生
  `moved` 提示（不 fail），**新增**收窄点才 fail。这条设计是刻意的——第一版实现按绝对行号 pin，
  在实现者自己同一次任务里就因「给 `value_fits_slot` 外面再加一个空行」而误报，属于**噪声护栏**；
  改为按 marker 身份后，「新增即 fail」这一核心不变式仍然成立（红演示即为证）。
- 每个点必须归入 `gated` / `pregated` / `safe` / `gate` 之一，理由写在 `PINNED` 里，与本报告 §3 表格一一对应。
- 已登记为 `PLAYBOOK` §3 的**门⑥**，在后续批次自动生效。

---

## 6. D-15 的分叉实现与**未端到端验证**的显式声明

**实现**：`ValueSlot` 新增 `FLOAT32`；`value_fits_slot` 的 32 位判定由
`p_slot == ValueSlot::FLOAT32 || (!REAL_T_IS_DOUBLE && p_slot == ValueSlot::REAL_T)` 决定 ——
即 **`FLOAT32` 在任何构建配置下都按 32 位判**，正确性来自代码结构而不是 `#ifdef`。

| 槽 | 用途 | 本构建（single） | 双精度构建 |
|---|---|---|---|
| `REAL_T` | 标量 `FLOAT` 成员、`Vector2`/`Vector3`/`Vector4` 分量 | 按 32 位判 | 按 64 位放行（正确：成员就是 `double`） |
| `FLOAT32` | **`Color` 分量**（`core/math/color.h:39-42` 声明 `float r,g,b,a`）、**`PackedFloat32Array` 元素** | 按 32 位判 | **仍按 32 位判** |

- `_container_element_slot(PACKED_FLOAT32_ARRAY)` → `FLOAT32`；
- `running_game_node_write.cpp` 的 `Color` 四个分量 → 新增 `COMPONENT_WIDTH_FLOAT32` → `ValueSlot::FLOAT32`
  （`Vector2/3/4` 分量仍是 `COMPONENT_WIDTH_REAL`，因为它们**真的**是 `real_t`）；
- 新增两个入口函数 `MCPTools::vector3_from_json` / `MCPTools::color_from_json`（把原来 file-private 的
  `_optional_vector3` / `_color_from_json` 提升到 `MCPTools` 命名空间并加声明），使 D-7 的两个实测点
  可以被 doctest **直接断言**（doctest 进程没有编辑器视口，测不到工具本身）。

**⚠️ 风险登记（`REPORT-023` 显式声明）**：本机只构建了单精度二进制（`SConstruct:192` 默认 `single`，
`--version` 亦为单精度），**D-15 没有做双精度端到端验证**，本次**不声称**已端到端验证。D-15 的证据是
**源码级 + 单元级**：`value_fits_slot(Variant(1e300), FLOAT32, …)` 的断言在被关闭的 doctest 用例里
（`TASK-023 D-15` 两条用例），而该断言在任何构建配置下都必须成立——这正是「与构建配置无关」的可测代理。
若将来要端到端验证，需要一次 `precision=double` 的重建（会替换被验二进制），建议作为独立任务。

---

## 7. 回归矩阵结果（M4c 反例矩阵 + D-5/D-6 段，**必须重跑**）

装置：同一个 `mcp023_narrowing_guardrail_evidence.ps1`（216 checks / 0 unexpected failures）。
反例 = `1e300` / `3.5e38` / `-3.5e38` / `"1e300"` / `1e-300` / `1e-46`；合法对照 = `1e30` / `1e-30` / `3.4e38`。

### 7.1 五条写路径 × 6 反例（全部仍闭合）

| 路径 | 6 反例错误码 | ② 无值回显 | ③ save 后文件 | ④ 另一读工具 |
|---|---|---|---|---|
| `editor_set_node_property` | 全部 **-32602** | 全部成立 | sha 不变、无 `inf`/`nan` | props `0.5` + gd `0.5` |
| `editor_set_node_property_batch` | 全部 **-32602** | 成立 | sha 不变 | props `0.5` + gd `0.5` |
| `editor_add_nodes_batch` | 全部 **-32602** | 成立 | sha 不变、**场景树无 `D4Node`** | gd `0.5` |
| `running_game_set_node_property`（9889） | 全部 **-32602** | 成立 | （游戏侧无 save；由 1/2/3/5 覆盖） | game props `0.5` + gd `0.5` |
| `project_set_node_property_across_scenes`（写盘） | 外层 **-32000**，`data.scenes.errors[0].reason` 即同一条 `-32602` 语义（`32-bit float` / `too small for`） | 成立 | `xscenes/good.tscn` sha **不变** | `load()` 读 `0.5|0.5` |

**合法对照**：路径 1 的 `1e30` / `1e-30` / `3.4e38` 全部 `code=0` 且回显有限（文件 sha 如预期变化）；
路径 1 的 `3.4e38` 正是 M4c 的边界对照（接受）与 `3.5e38`（拒绝）的**同一对断言**。

### 7.2 D-5 / D-6 段（未回退）

- **D-5**：`project_create_resource(Curve)` 的 `properties_set` / `changed` / `ignored` 与独立 GDScript 回读一致；
  `min_value=1e300` 仍在**创建文件之前** `-32602`；`project_edit_resource` 的 `changed` 形状不变。
- **D-6**：游戏侧写 `user://mcp_test_report.json` → 编辑器侧 `editor_get_test_report` 读回
  （`source=game_process_file`、`report_source_process=game`）；`clear` 的跨进程语义（文件被删、下一次 `total=0`
  + `no_results=true` + `report_file_present=false`）不变。
- **TASK-020/021 面**：五种分量拼写、七种字符串拼写仍全部 `-32602`；合法字符串 `"1.5"` 仍写入；
  `editor_execute_gdscript` 第二通道自检 `return 42` → `42`。

---

## 8. 逐工具表（本任务改动的工具；按 PLAYBOOK §4 的列）

| `new_name` | 迁移源位置（**仅类别参考**） | 引擎依据（用了哪个 API / 为何这是自然形态） | 自然契约 | C++ 落点 | 与迁移源的差异及理由 |
|---|---|---|---|---|---|
| `editor_set_viewport_3d_camera` | `editor.rs:635` | `EditorInterface::get_editor_viewport_3d()` → `SubViewport::get_camera_3d()`；`Camera3D::set_global_position/set_rotation_degrees/look_at/set_fov` | 不变（契约逐字不动）；**值不变时行为变化**：`position`/`rotation_degrees`/`fov` 里放不进 32 位浮点的数 → `-32602` 而非静默 `inf` | `tools/editor_write_scene_editor.cpp:137-176`（`MCPTools::vector3_from_json`）、`:781`（fov） | **正经修正**：迁移源用 `as_f64().unwrap_or(0.0)` 且直接 `Vector3(...)`，D-7 实测「`code=0` + `inf`」即由此而来；PLAYBOOK §6.6「工具真的能用」优先 |
| `editor_setup_world_environment` | `scene_3d.rs:162` | `WorldEnvironment::environment` + `Environment::set_background/set_bg_color/set_ambient_source/set_ambient_light_color` | 不变；`bg_color`/`ambient_color` 的分量放不进 32 位浮点 → `-32602`（且**任何写入之前**） | `tools/editor_node_setup.cpp:114-152`（`MCPTools::color_from_json`） | 同上（M4c 实测 `Color(inf, 0, 0, 1)` 曾落 `.tscn`） |
| `editor_simulate_mouse_click` / `editor_simulate_mouse_move` / `editor_simulate_input_action` / `editor_simulate_input_sequence` | `input.rs:*` | `Input::parse_input_event()` + `InputEventMouse*::set_position/set_global_position/set_relative`、`InputEventAction::set_strength`（后者自带 [0,1] 夹取） | 不变；坐标/`strength` 放不进 32 位浮点 → `-32602`（序列里点名 `events[i].x`） | `tools/editor_input_simulation.cpp`（`_number_fits_event` + 4 处调用点） | 迁移源注入前不做可表示性判定；本轮把它与写路径同标准 |
| `running_game_play_input_recording` | `mcp_runtime_agent.gd` | `InputEvent*::set_position/set_relative/set_strength`（回放路径） | 不变；`events[i].position/relative/strength` 越界 → `-32602`（在**开始等待之前**拒绝） | `tools/running_game_input.cpp`（`_event_number_fits` + `_event_vector2`/ACTION 分支） | 同上 |
| `running_game_run_test_scenario` | `mcp_runtime_agent.gd` | 同 `InputEventAction::set_strength` | 不变；`steps[i].strength` 越界 → `-32602`（整场景**注入前**校验，坏 step 7/10 不注入任何 step） | `tools/running_game_test_execution.cpp:165-176` | 迁移源无该校验 |
| `running_game_find_nearby_nodes` | `mcp_runtime_agent.gd:535` | `Node::get("global_position"/"position")` + `Vector2::distance_to` | 不变；`position.x/y`、`radius` 越界 → `-32602`（否则 `distance <= inf` 会把全部节点判为「附近」） | `tools/running_game_read_scene.cpp` | 迁移源无该校验；这是**读**工具的诚实性 |

> 本任务**不新增工具**（113/171 不变），也不改任何 `description`/`inputSchema`，因此契约为零改动
> （门① 的逐字断言不变）。

---

## 9. 规范改动（GDR-24 / 门⑥）

- `docs/DESIGN-DETAIL.md`：§15 索引加 **GDR-24** 行；新增 **§22 GDR-24 收窄点必须显式标注且被机器检查**
  （§22.1 专用 setter 覆盖规则、§22.2 `FLOAT32`/`REAL_T` 拆分与风险登记、§22.3 门⑥的实现、
  §22.4 与 GDR-22 的关系）。
- `docs/tasks/PLAYBOOK-group-port.md` §3：新增**门⑥**行 + 说明块（为什么它必须是独立一道门、
  四种形态 + 一种构建配置形态的历史、`FLOAT32` 的理由）。

> 两处都在 `modules/mcp_server/**` 内，符合任务书「只允许改 `modules/mcp_server/**`」；
> **未创建任何竞争性规范/决策文档**（未新建 `DECISIONS.md`、未新建 `docs/spec/**`）。

---

<!--DEVIATIONS-->

## 10. deviations（与手册/任务书的偏离，逐条显式列出）

1. **`fov` 也过闸门**：任务书 §1 说 `fov`「同源但被引擎范围校验挡住（**仅作登记**）」。本实现**仍对它加了
   `-32602` 闸门**（`1e300`/`3.5e38` 拒绝），理由是任务书 §1.1 要求「这些路径的每个分量在写入之前走同一道闸门」，
   且 `(real_t)fov` 与另两个分量完全同类；`fov=180`（数放得进 32 位、引擎自己拒绝）仍回 `code=0` 并如实回显
   `70.0100021362305`，**引擎语义未被改变**。若验收方认为 `fov` 不应拒绝，请按「登记即可」裁决。
2. **`running_game_find_nearby_nodes` 也加了闸门**：它是**读**工具，任务书只要求「找出其余收窄点并判定」。
   我判定它**需要修**（`position.x=1e300 → (real_t) → inf`，`distance <= inf` 会把全部节点判为「附近」，
   `radius=1e300` 同理，`1e-300` 则把搜索点静默挪到原点），属于「工具真的能用」标准下的诚实性问题。
3. **`editor_save_scene` 的 sha 判据改为「内容指纹」**（§4.3 的说明）：任务书 §4③ 要求「sha256 不变」，
   但引擎文本保存器**每次保存都换随机资源后缀**，字节 sha 结构性不可能不变。本报告保留字节级断言
   （无 `inf`/`nan`/`Color(inf`）并改用「归一化随机后缀后的内容指纹不变」作为等价判据；
   **D-4 的五条写路径矩阵仍按原样比对真实 sha256 且全部不变**（那些用例的场景已带 `ext_resource`，
   M4c 当年也是这么测的——本装置在 `W_bg_color`（`WorldEnvironment` 新建）上才第一次触发该引擎行为）。
4. **门⑥ 的 pin 身份是 marker 而不是行号**（§5）：第一版按绝对行号，同一次任务内就因代码移动误报；
   改为「文件 + marker id + 出现次序」。核心不变式（**新增未标注收窄点即 fail**）由红演示证明。
5. **`(int)`/`(uint8_t)` 收窄不在门⑥ 的扫描模式内**（§3 末的范围声明）：任务书点名的是六个模式；
   这两个模式的真正值面已由 GDR-22 覆盖，其余是枚举/错误码格式化。
6. **未新建决策日志**：任务书禁止新建规范/决策文档，因此 `DECISIONS.md` 未在 fork 内创建；
   `REPORT-023` 与 `docs/DESIGN-DETAIL.md` §22（任务书 §3.2 明确要求写进该文件）共同承担记录职责。

## 11. blockers

无。（9877 全程 = 36392；9888/9889 收尾均无监听；无孤儿进程；未 push。）

## 12. next_step_recommendation

1. **请独立验收方重点复核**：(a) §3 清单里 15 个 `safe`/`pregated` 点的**理由是否成立**（尤其
   `running_game_node_write.cpp` 的 5 个 pregated 点——「对象已被 `_check_components` 重建」是要害）；
   (b) 门⑥ 的**红演示**（自行插入一个未标注收窄点，确认 fail 且 exit 1）；(c) D-15 的**未端到端验证**声明
   是否被接受为风险登记而非缺陷。
2. **接受「拒绝不再创建 `WorldEnvironment`」为同一 D-7 的修复**（§4.3）：该断言目前是**单元级**
   （新增 doctest 直接打 `setup_world_environment_on`，断言 `child_count()==0`）+ **线上的文件指纹**
   （证据运行 `W_bg_color_file_clean` PASS，前后内容指纹一致）。建议验收方用「拒绝后 `editor_get_scene_tree`
   里没有 `WorldEnvironment`」这条**独立**读通道再验一次（本轮未单独构造该条，如实登记）。
3. **建议后续任务**：(a) 一次 `precision=double` 的构建 + 端到端 D-15 验证（会替换被验二进制，需独立任务）；
   (b) 顺手性审计的 D-8…D-14（M4c 已给出引擎正解 API + 行号）仍挂在 `REPORT-AUDIT-M4c.md` §10，与本任务无关但未闭合。
