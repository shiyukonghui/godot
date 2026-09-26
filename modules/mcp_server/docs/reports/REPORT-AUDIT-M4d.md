# REPORT-AUDIT-M4d — 第四次独立验收（M4 = B3+B4 = 47 工具 + GDR-23/25 顺手性）

> 独立验收方（未参与实现）。**未采信**任何 `REPORT-*`（含实现报告）与决策者结论；
> 本报告每一条结论都来自**本次自行构造并跑出的证据**。历史三份审计报告仅用于了解背景，不作为判据。
> `verdict`、逐项证据、`defects`、`unconfirmed`、`risks` 见文末。

## 0. 基准与开工

| 项 | 值 |
|---|---|
| HEAD | `ac06a1cadede2db19331a2d28181f85bcf511964`（分支 `feature/mcp-server-module`） |
| 开工重建 | `modules\mcp_server\scripts\build_local.cmd -Force`（`tests=yes`），scons **exit 0**，日志 `%TEMP%\audit-m4d\build_m4d.log`（未抑制 scons 输出） |
| `--version` | `4.8.dev.custom_build.ac06a1cad` → 前缀 == `git rev-parse --short HEAD`（`ac06a1cad`）**一致**，不是陈旧二进制 |
| 对等基准 | `docs/tools_list.renamed.json`（171 条，sha256 `4492a0f7bbfc9785a84abeff65ff87b8032d8d14770922f061335ba9fea77535`）、`docs/tool-rename-map.json`、`docs/tool-groups{,-b2,-b3,-b4,-b5}.json` |
| 已实现 | 57 组中 `implemented=true` **31 组**，并集 **113 工具**；编辑器端点 91、游戏端点 53 |
| 端口 | 用户编辑器 **9877 全程 PID 36392**（每个脚本前后各校验一次）；测试 9888/9889；另开并已释放：9892（探针编辑器）、9895/9896/9897/9898 与 E-10 自动挑出的 50434、52908 |
| 证据形态 | 一律 `curl.exe -s -o <file>`（`-w %{http_code}`）+ sha256，请求体一律 `ConvertTo-Json`；响应体不经管道 |
| 环境 | Windows PowerShell 5.1；所有审计脚本**纯 ASCII**（9 个中文字节曾导致一次解析失败，已修正并重跑） |

命令退出码：本轮 `a_parity`/`b_recheck`/`c_gate6`/`d_roundtrip`/`d_play_recheck`/`e_recheck`/`e_lost` 全 0；
`b_silent`/`d_ergo`/`d_play`/`e_security`/`e_recheck2` 的退出码非 0 **全部**由本报告 §B/§D/§E 逐条说明的
「验收脚本自身的判据错误」造成，其中 **1 条是真实缺陷**（`O3` → D1）。

## A. 全量对等与 scope（16/16 PASS）

- **A0** 契约 171 条；`implemented=true` 组并集 **113**。
- **A3b** 两端点 `tools/list` 均 HTTP 200 且正文非空：编辑器 **27595 B**、游戏 **18401 B**。
- **A4/A5**：**结构化解析 `name` 字段**（全程无 `-match`/文本包含）后与并集比对：
  编辑器 live=91 / expected=91（missing 空、extra 空）；游戏 live=53 / expected=53（missing 空、extra 空）。
- **A6/A7 逐字门**：**91/91** 与 **53/53** 的 `name`、`description`、`inputSchema`（canonical 化后）**全部逐字相等**，
  mismatches 为空。
- **A8/A9 顺序确定性**：同一进程重复 `tools/list` 的响应 sha256 相同
  （`6e85b1db9f78db5739b5c78161c91670ba6b5ab28fbe228639851b4c503d5402`）；
  **停掉编辑器并用同一二进制重新起一个独立进程**后 sha256 **仍相同**（跨进程重启一致，§17.4）。
- **A10/A11 跨端点**：编辑器调 `running_game_find_nearby_nodes` → `{"code":-32601,"message":"Method not found: running_game_find_nearby_nodes"}`；
  游戏调 `editor_get_errors` → 同样 `-32601`。**未执行**（`-32601` 是方法不存在，不是执行后的失败）。
- **A12** `_meta.overrides` = **13 条**：`description:{search_files,search_in_files,uid_to_project_path,project_path_to_uid,play_scene,replay_recording,find_signal_connections,find_node_references,analyze_signal_flow,get_test_report}` × append + `inputSchema:{play_scene,replay_recording,get_test_report}` × replace。
- **A13 override 纪律（最强形态）**：用 `gen_renamed_contract.py --out <临时文件>`（v1.7.0，`self-checks = OK (lint 171/171, unique 171/171, disposition enum OK)`）
  重新生成契约，**生成结果与被跟踪文件逐字节相同**（`4492a0f7…`）。该生成器对任何未声明 override 的
  `description`/`inputSchema` 变化都会 `FATAL` 退出（`gen_renamed_contract.py:586/588`），
  因此字节相同同时证明：**除这 13 条 override 与指纹字段外没有任何其它契约改动，也没有手改**。
- **A14** 9877 前后均为 PID 36392。

## B. 「静默写错值」五形态（每条四形态证据）

> 判据（§20.5）：①`-32602`；②拒绝响应**无值回显**；③**显式保存后文件字节扫描**无 `inf`/`nan`；
> ④**另一个读工具**读到旧值未变。下表每条都取了四形态。
>
> **证据边界（诚实声明）**：编辑器端点上每一例都取齐了四条；游戏端点（`running_game_*`）的写路径**不落盘**，
> 其 ③ 由构造即不适用（该例的 ③ 字段记录为 `n/a (no file is written on this path)`），因此游戏侧给出 ①②④ 三条；
> ③ 的「保存后文件干净」由编辑器端点的同值反例承担。

| 形态 | 反例（编辑器端点 / 游戏端点各一遍） | ① | ② | ③（`editor_save_scene` 后扫 `.tscn` 字节） | ④（另一个读工具） |
|---|---|---|---|---|---|
| ① 整值 | `editor_set_node_property{path:Actor,property:position,value:1e20}`、`value:1e-300`；`running_game_set_node_property` 同 | `-32602` | 无 `new_value/old_value` 键、无非有限数值 | `present=False hits=`，sha256 记录在案 | `editor_get_node_properties` / `running_game_get_node_properties` 仍为旧值 |
| ② 分量 | `position:{x:"abc"|"NaN"|null|{}|[]|1e300|1e-300}` × 2 端点 = 14 例 | 全 `-32602`（消息含 `Parameter 'value.x'`） | 同上 | 同上 | 同上 |
| ③ 标量 | `rotation:1e300 / 3.5e38 / 1e-300 / "abc" / "1e300"` × 2 端点 = 10 例 | 全 `-32602` | 同上 | 同上 | 同上 |
| ④ 专用 setter | `editor_set_viewport_3d_camera.position/rotation_degrees/fov`、`editor_setup_world_environment.bg_color/ambient_color` | 全 `-32602` | 同上 | 同上 | `editor_get_viewport_3d_camera` / `editor_get_node_properties(environment)` 未变 |
| ⑤ 构建配置 | 见下 | — | — | — | — |

拒绝消息（自行跑出的原文）：`Parameter 'bg_color.r' is the number 1e+300, which does not fit in the 32-bit float
component of the Color an Environment setter stores: the engine's own copy would write inf instead of the value you
sent. The largest 32-bit float is about 3.4e38.` / `Parameter 'fov' … Camera3D::set_fov …` /
`Parameter 'position.x' … Vector3 this camera setter stores …`。

**同族新面（自己找的，10 例）**：
- 编辑器 + 游戏两端的 `Color` 分量 `{r:1e300}` → `-32602`；
- `Polygon2D.polygon` 的 packed 元素 `[{x:1e300,y:0}]` → `-32602`（消息 `Parameter 'value[0].x'`）；
- `editor_set_node_property_batch`（`node_type=Node2D, position:{x:1e300}`）→ `-32602`，且 Actor 旧值未变；
- `editor_add_nodes_batch`「**好 + 坏 + 好**」→ `-32602 nodes[1]: cannot instantiate node type 'NoSuchEngineClassAtAll'`，
  **场景树未变**（零半成品）；
- `editor_set_node_property` 的 `properties` 缺失/类型错 → `-32602`；`position:true` → `-32602`；
- `project_set_node_property_across_scenes` 坏值 → `-32000`（结构化列出每个场景的拒绝理由）+ **磁盘 sha256 不变**；
- `project_create_resource`/`project_edit_resource`：`Curve.min_value=1e300` → `-32602` 且**文件未创建/未改动**；
  `AudioStreamWAV.data=[300]`（`uint8` 元素槽）→ `-32602` 且未创建；
- `project_set_setting`（登记为 `WIDE` 槽）：`key=mcp_audit_wide, value=1e300` → **code 0**，回读 `1E+300`（Double），
  即「宽槽不误拒、回读诚实」——与 §20.2 的登记一致。

**合法值对照**：`position:{5.5,-6.25}`、`rotation:1.5`、`bg_color:{0.25,0.5,0.75}` 均 code 0 且读回等于所写。

**扫描器自证**：对含 `Color(inf, 0, 0, 1)` 的探针文件，本报告使用的文件扫描器 `present=True hits=inf@…`，
所以「文件干净」的结论不是扫描器失灵造成的假绿。

### 形态⑤（构建配置）：`FLOAT32` 与 `REAL_T` 已分离，风险登记诚实

- 源码级：`core/math/color.h:39-42` `float r = 0.0f; float g = 0.0f; float b = 0.0f; float a = 1.0f;`
  ——`Color` 分量**恒为 32 位**。
- 源码级：`tools/tool_helpers.cpp:1068-1074`
  ```cpp
  const bool judge_32_bit =
          p_slot == ValueSlot::FLOAT32 ||
  #ifdef REAL_T_IS_DOUBLE
          false;
  #else
          p_slot == ValueSlot::REAL_T;
  #endif
  ```
  `FLOAT32` 的「恒判 32 位」**不在任何预处理分支里**，所以它在 `precision=double` 构建下不会复活
  （正确性来自代码结构而非构建配置）。
- 单元级：`tests/test_mcp_server.h:13689` `TEST_CASE("[MCPServer] TASK-023 D-15: the FLOAT32 slot is judged in every build, REAL_T follows the build")`
  断言 `FLOAT32` 拒绝 `1.0e300/3.5e38/-3.5e38/1.0e-300/1.0e-46`、接受 `0/0.3/1.0/-1.5/1.0e30/-1.0e30/1.0e-30`，
  用例体内**没有** `#ifdef REAL_T_IS_DOUBLE`（`REAL_T` 的那一半用 `if (sizeof(real_t) == 4)` 守卫）。
- **风险登记诚实性**：`DESIGN-DETAIL.md:703` 与 `REPORT-023` §6/§4 明确写「本机只构建单精度二进制，
  **未做双精度端到端验证**」「D-15 的证据是源码级 + 单元级」「**不声称**已端到端验证」。
  本机确实无法端到端验双精度（重建 `precision=double` 会替换被验二进制），故本项按「源码级 + 单元级」评审，
  未发现夸大或掩盖。**无缺陷**。

## C. 门⑥（收窄点清单）对抗实验（30/30 PASS）

被验脚本：`modules/mcp_server/scripts/check_narrowing_points.py`（扫描 `tools/**`，模式
`(real_t)`/`(float)`/`Color(`/`Vector2(`/`Vector3(`/`Vector4(`）。

| 实验 | 期望 | 实况 |
|---|---|---|
| 静止 | exit 0 | **exit 0**，`scanned=30 pinned=30 unannotated=0 unlisted=0 stale=0` |
| 插入**未标注**收窄点 `const real_t audit_probe_a = (real_t)1.0e300;` | exit 1 | **exit 1**，报告点名 `tools/running_game_read_scene.cpp:399 …`（文本模式含 `carry no`） |
| 插入**已标注但未登记**的标记 `// MCP-NARROWING: G24-AUDIT-NOT-REGISTERED` | exit 1 | **exit 1**（`unlisted`，文本模式含 `no pin`） |
| **删掉标记**（保留收窄代码） | exit 1 | **exit 1**（`stale` + `unannotated`，`pinned=1 found=0`） |
| 删掉收窄代码（保留标记） | exit 1 | **exit 1**（陈旧条目 `stale`） |
| **只加 8 行空行**（全文件位移） | 不假红 | **exit 0**，`moved: G24-ENV-COLOR-COMPONENT pinned_line=150 now=158`（只是 note） |
| **把一个已登记的点整体移动**（含标记注释与代码行，150 → 904） | 不假红 | **exit 0**，`moved: pinned_line=150 now=904` |
| 还原 | 字节相同 | 两个被改文件的 sha256 与备份**逐字节相同**；`git status --porcelain` 只剩既有未跟踪物 `.graphifyignore / build-m0.cmd / graphify-out/ / install-deps-m0.cmd` |

**索引方式核实**：上面「只加空行」与「整体搬移」两例下 exit 仍为 0、且只报 `moved` note，说明查表键是
`(file, marker id, 该文件内该标记的出现序)`，**不是行号**（若按行号查表，两者都会 `UNLISTED` 假红）。
这与脚本 `report()` 的实现（`matched[(file, marker)]` 计数 + `pin["line"]` 仅作文档）一致。

### C-defect：门⑥ 可被常见拼写绕过（**5 例实证**）

在自己找的同族新面上，以下**未标注的收窄点**插入后门⑥ **exit 0**（扫描器 0 命中），
而把同一个值写成 `(real_t)` 时立刻 exit 1（对照）：

| 探针 | 门⑥ exit | 扫描器是否看见该点 |
|---|---|---|
| `const real_t audit_probe_c = 1.0e300;`（隐式 double→real_t） | **0** | 否（0 个 audit_probe 点） |
| `const float audit_probe_d = static_cast<float>(1.0e300);` | **0** | 否 |
| `const Color audit_probe_e = ::Color(1.0e300, 0.0, 0.0, 1.0);` | **0** | 否 |
| `const Vector3 audit_probe_f = Vector3{1.0e300, 0.0, 0.0};` | **0** | 否 |
| `const Color audit_probe_g = Color` 换行 `(1.0e300, 0.0, 0.0, 1.0);` | **0** | 否 |
| 对照：`const real_t audit_probe_h = (real_t)1.0e300;` | **1** | 是（`unannotated`） |

即：§22.3 与脚本 docstring 声称的「**每个**收窄点都必须标注」「新增收窄点而不标注 = 门失败」
在**拼写层面**不成立。当前树内 30 个点全部合规（无既有缺陷），但门槛的**覆盖面**被高估：
一个实现者用最常见写法 `const real_t x = 1.0e300;` 或 `static_cast<float>` 就能静默新增第 5 种形态。

## D. 顺手性八项（GDR-23/25）

### D1 E-10 / §23.2 `editor_play_scene` 端口注入（9/9 PASS after re-check）
- 子进程 **cmdline 实测**（按注入端口在全部进程里匹配，因为游戏是 console 包装器的**孙进程**）：
  `...\godot.windows.editor.x86_64.exe --path C:/…/proj/play2 --remote-debug tcp://127.0.0.1:6007 --editor-pid 66932 --scene res://scenes/main.tscn "--mcp-port=9897"`
  ——编辑器自己那条是 `--mcp-port=9888`，是**另一个进程**；注入的实参被引擎加了引号（`"--mcp-port=9897"`）。
- 显式端口：`mcp_port=9897` → code 0，`mcp_port_source=argument`，`endpoint=http://127.0.0.1:9897/mcp`，
  `pid=64360` **恰是** cmdline 里带该端口的那个进程；在该端口上 `running_game_get_scene_tree` code 0。
- 自动端口：`mcp_port=52908`、`source=auto_free_port`、`pid=51748`，cmdline 同样带 `--mcp-port=52908`，端点可用。
- 诚实错误：`mcp_port=9888`（编辑器自己）→ `-32000` + `data.suggestion`；
  `mcp_port=9896`（本审计自己占用的端口）→ `-32000` + suggestion；
  两次调用前后 **godot 进程数不变**（3 → 3，**没有起游戏**）。
- `editor_stop_scene` 后，带注入端口/该工程的进程数为 0（无孤儿）。

### D2 E-1/G-2 场景依赖
`project_get_scene_dependencies('res://scenes/main.tscn')` →
`{"count":1,"dependencies":[{"declared_type":"Script","path":"res://scenes/actor.gd","path_source":"scene_path","type":"GDScript","uid":""}]}`
——`type` 是**真实类型** `GDScript`（不是空串），`path` **原样**喂给 `project_read_scene_file_content` → code 0。

### D3 E-3/§23.4 读回↔写回双向闭合
- 编辑器端点 **12 项**、游戏端点 **4 项**（Vector2/Vector2i/Vector3/Rect2/Color/PackedVector2Array/float/int/bool），
  每项走「写 V0 → 读 R1 → **把 R1 原样写回** → 读 R2」三层，**12/12 + 4/4 在 1e-5 内相等**。
- 其中 **11/12 位精确相等**；唯一非精确项 `Camera3D.rotation_degrees` 有 **1 ulp** 漂移
  （`10 → 9.99999904632568 → 9.99999809265137`），原因是它是 `rotation`(弧度) 的**派生属性**，
  每次读写都过一遍「度↔弧度」转换。这是引擎语义，不是本模块的错值，已在报告中显式声明。
- 资源侧：`project_read_resource` 读出的 `Gradient.colors/offsets` **原样**写回 `project_edit_resource` → code 0，再读相同。

### D4 §23.5 OBJECT（两端点一致）
未设置 → 读回 **`null`**（不是 `{}`）；写 `{}` → `-32602`（消息解释 `{}` 既不是清除也不是合法引用）；
写 `null` → code 0 且读回 `null`；写 `"res://env_obj.tres"` → 读回 `{"path":"res://env_obj.tres","type":"Environment"}`，
把该对象**原样写回** → code 0、再读相同；`{"type":"Gradient","path":"…gradient.tres"}` 写到 Environment 属性 →
`-32602`（消息给出 expected `Environment` / got `Gradient`）。

### D5 E-9 `project_read_resource` + 限量/截断
`Environment`（101 个存储属性）→ `returned=64`、`truncated=true`、`dropped=37`、
`limits={"max_properties":64}`、`message="64 of 101 stored properties returned; 37 omitted by the tool's limit"`；
小资源 `Curve` → `truncated=false`。

### D6 E-6/G-4 日志来源与归属进程
`editor_get_errors`：`source=editor_log`、`process=editor`、`editor=true`、`port=9888`、`pid=66052`、`in_process=true`、
`log_path=user://logs/godot.log`；`editor_get_output_log` 同源同进程。两工具字段集合**只差** `errors` / `lines`
（`union=available,count,editor,errors,in_process,log_path,note,pid,port,process,source`）。
无匹配的 `filter` → code 0 + `count=0`（**不是** `-32603`）。
**跨进程隔离实测**：在**游戏进程** `print("AUDIT_M4D_GAME_MARKER_7731")` 后，
编辑器端点 `editor_get_output_log(filter=marker)` 返回 `count=0 source=editor_log editor=true`——
**没有把游戏进程的行当成自己的**。

### D7 E-2/E-8 编辑器节点路径
`editor_get_scene_tree` 的 7 条 `path` 为 `., Actor, VP, Cam, Poly, Spr, WorldEnv`（相对编辑场景根），
**不含 `@EditorNode@`**；两个**独立进程**启动后路径列表**逐字相同**（本机甚至整包响应 sha256 也相同：
`3b2e0fdc…`）；坏路径错误消息 `Node 'NoSuchNode' not found` **不含** `@EditorNode@`。
（该响应**额外**带一个 `absolute_path` 字段，内含 `@EditorNode@20539/…`；它在
`tools/editor_read_scene_inspector.cpp:336-348` 被显式注释为「保留给确实想要的调用方的诊断字段、不再是主字段」，
故不算违反 E-2，但见 `risks`。）

### D8 G-1 子属性路径
`editor_set_node_property{path:Actor, property:"position:y", value:9.5}` → code 0
（回显 `new_value:9.5 / parent_new_value:{x:3.0,y:9.5}`）；**另一个工具** `editor_get_node_properties` 读回 `{"x":3.0,"y":9.5}`。
负例：不存在子段 `position:zzz` → `-32001` + `data.suggestion="'Vector2' has these members: x, y"`；
不可 index `rotation:x` → `-32602` + 说明。

### D9 G-3 `clear` 缺省纯读
桥接文件 `%APPDATA%\Godot\app_userdata\mcp_audit_m4d_ergo\mcp_test_report.json`（由两条
`running_game_assert_node_state` 写入 pass=1/fail=1）。
- 缺省调用两次（**同 id、同请求体**）：响应 sha256 **相同**（`5575195…`），桥接文件**仍在**，`cleared=[]`，`total=2`；
- 显式 `clear:true`：`cleared=["editor_process","game_process_file"]` 且桥接文件**消失**；
- 显式 `clear:false`：`cleared=[]`（纯读）；
- **线上** `tools/list` 的 `inputSchema.properties.clear.default` = **`false`**（type Boolean），
  与契约文件一致，也与上面观测到的行为一致。

### D10 零字符串手术链（≥2 条、跨 ≥4 工具，逐步 0 次字符串处理）
- **链 1（编辑器，6 工具）**：`editor_open_scene` → `editor_get_scene_tree`（按 `name -ceq 'Actor'` 取 `path` 字段）
  → `editor_get_node_properties`（`{"x":3.0,"y":4.0}`）→ `editor_set_node_property`（原样写回同一对象）
  → `editor_get_node_properties`（相同）→ `project_get_scene_dependencies` → `project_read_scene_file_content`（41 B）。
- **链 2（游戏，5 工具；另一条经 E-10 注入端口的 6 工具链）**：`running_game_get_scene_tree` → `running_game_get_node_properties`
  → `running_game_set_node_property` → `running_game_get_node_properties` → `running_game_assert_node_state`（`passed=true`）
  （经注入端口版本还含 `editor_play_scene` 与 `editor_stop_scene`，其中 `editor_play_scene` 连端口都取自响应）。
- **逐步字符串处理次数**：把每条链的源码区间（`CHAIN-BEGIN..END`）单独取出，扫描
  `Split / Replace / Substring / Trim / IndexOf / Remove( / -replace / -match `：
  **0 次**（3 个区间各 0：`d_roundtrip` 的 CHAIN1 1531 字符、CHAIN2 1222 字符，`d_play` 的 CHAIN2 1467 字符）。唯一对字符串做的操作是**相等比较**（`-ceq`）用于选取节点，
  以及 `[string]` 类型转换；没有任何「先转形/剔除装饰再喂回」的动作。

## E. 延迟通道 / 事务 / 安全

- **延迟超时（§18.4）**：`running_game_find_node_when_available{node_path:NeverAppears, timeout:60}` →
  **框架把自报 60 s 收紧为 30 s**，以 `-32000` + `data.timeout_ms=30000` + `data.suggestion` 收尾，
  实际耗时 28.45 s（**不是静默丢弃**）。
- **不饿死常规请求（§18.3）**：pending 期间 `GET /mcp` 分别 **25 ms / 22 ms** 返回
  （`pending=1, pending_connections=1`），主线程未被阻塞。
- **断连即清理（§18.5）**：请求发出后直接关闭连接，3 s 后 `pending=0 pending_connections=0`（无泄漏）。
- **批量中间坏元素**：`editor_add_nodes_batch`「好 + 未知类型 + 好」→ `-32602 nodes[1] …`，场景树**未变**（零半成品）。
- **跨场景「好文件 + 坏文件」全或无**：`res://scenes`（`good.tscn` + 故意损坏的 `bad.tscn`）→
  `-32000 "Refusing to write: 1 scene(s) …"`，`data.scenes.errors=[{scene:bad.tscn, reason:not a loadable PackedScene}]`，
  `good.tscn` sha256 **不变**；当值也非法时，同一次拒绝**同时列出两个场景**的错误
  （`planned_before_refusal=[]`，`suggestion="Nothing was written…"`）。
- **正向对照**（把坏文件移走、两个可加载场景）：同一调用 code 0，
  `scenes_affected=[good.tscn:live_open_scene:1, side.tscn:offline_saved:1]`，
  **关闭的 `side.tscn` 落盘真的变成 `Vector2(3, 4)`**——说明拒绝语义不是「这个工具根本不写」。
  **但 `live_open_scene` 那一半是假的**，见 **defect D1**。
- **路径逃逸（读侧 8 例全拒）**：`/etc/passwd`、`C:\Windows\win.ini`、`C:\Users\wyl\.ssh\id_rsa`、
  `res://../escape.txt`、`res://scenes/../../escape.txt`、`res://..\escape.txt`、`\\localhost\C$\Windows\win.ini`、
  `///C:/Windows/win.ini` → **全部 `-32602`**，无一次读到工程外文件。
- **路径逃逸（写侧 3 例全拒）**：`res://../escape_probe_1.tscn`、`res://../../escape_target/escape_probe_2.tscn`、
  绝对路径 `C:\…\audit-m4d\escape_target\escape_probe_3.tscn` → 全 `-32602`，且**目标处没有任何文件被创建**。
- **前缀碰撞**：`project_search_file_contents(path='res://scenes', pattern=<res://scenes2 内的标记>)` → `count=0, matches=[]`
  （`res://scenes` **不**扩张到兄弟目录 `res://scenes2`）；同一标记从默认根搜索时 `count=1`
  （`project_search_file_names` 找到 `res://scenes2/secret_marker.txt`），证明文件确实存在、是过滤器在起作用。
- **符号链接逃逸**：`New-Item -ItemType SymbolicLink` 在本机无提权/开发者模式下失败，**未能构造**，记为 `unconfirmed`。
- **参数滥用**：缺必填 → `-32602`；`position:true` → `-32602`；`properties` 用字符串 → `-32602`；
  `count=-1` → `-32602`；未知工具 → `-32601`；`arguments` 传 `[]` → `-32602 Invalid arguments: expected an object`；
  裸 `NaN` 字面量 → **HTTP 400 + `{"code":-32700,"message":"Parse error","id":null}`**
  （§6 只规定「非法 JSON → -32700 且 id 为 null」，未规定 HTTP 状态，故符合规范）。

## F. 工程门与端口纪律

> 方法说明：本机 PowerShell 5.1 通过 `Start-Process -PassThru` 取不到子进程退出码（gate①/③/④/⑤ 四次都返回空字符串），
> 因此凡涉及退出码的判据，本报告一律用**该门自己打印的结论行**作为证据，并在下面逐条给出原始行。
> 第一次 `g_gates.ps1` 还因为「引擎工作目录不对」+ `$ErrorActionPreference='Stop'` 对 stderr 报错而**中止**（engine 报
> `ERROR: Test data directory not found … repository root.`）；修正为 `-WorkingDirectory <repo root>` 后重跑，下面都是修正后的结果。

| 门 | 命令 | 结果 |
|---|---|---|
| ① 契约子集逐字（**5 组**） | `check_contract_subset.ps1 -Group <g>`，g ∈ {project_read_template, editor_node_write, running_game_assertion, editor_testing_read, project_setting_write} | 每组 `3/3 checks passed`、**0 个 FAIL 行**（合计 15 例 PASS）；每组都打印 `implemented_union=91 tools (editor endpoint) / 53 tools (game endpoint)` 与 `PASS guard_user_port_9877` |
| ③ 模块 doctest | `--headless --test --test-case=[MCPServer]*`（工作目录 = 仓库根） | `test cases: 219 | 219 passed | 0 failed | 1429 skipped`；`assertions: 8443 | 8443 passed | 0 failed`；`Status: SUCCESS!` |
| ④ 全引擎回归 | `--headless --test` | `test cases: 1645 | 1645 passed | 0 failed | 3 skipped`；`assertions: 432725 | 432725 passed | 0 failed`；`Status: SUCCESS!` |
| ⑤ 批次收口 | `accept_m1.ps1` 连跑两次 | run1 **22/22 cases passed**、run2 **22/22**，两次 `PASS/FAIL` 清单**逐条一致**（各 22 条、0 FAIL）；两次都打印 `implemented tools = 91 (editor endpoint) / 53 (game endpoint); contract = 171; known_deviation = per-batch verbatim gate only` |
| ⑥ 收窄点清单 | `python check_narrowing_points.py` | **exit 0**（`scanned=30 pinned=30`）；对抗实验见 §C |

端口与进程纪律（全部由本报告自行观测）：

- **9877 全程属用户 PID 36392**：`a_parity`/`d_play`/`g_gates`/`g_gates2`/`h_fix` 每次开跑前后各查一次，
  所有结果均为 `pid_before=36392 pid_after=36392`。
- **测试端口 9888/9889**：每轮门/脚本开始前 `owner=-1`（空闲），结束后 `owner=-1`（已释放）。
- **本轮其它端口全部释放**：9892（探针编辑器，已 kill 并核对其子进程）、9895/9896/9897/9898、
  E-10 自动挑出的 50434 与 52908 —— 收尾时 `netstat` 无 LISTENING、进程表中**只剩 36392 一个 godot 进程**。
- **无孤儿**：`Get-CimInstance Win32_Process | Name LIKE '%godot%'` 在每轮结束与总收尾时均为 1 条（用户那个）；
  `editor_play_scene` 拉起的游戏子进程在 `editor_stop_scene` 后按注入端口查询必为空（E-10 的两条链各验证一次）。
- **无 git 写操作、无被跟踪文件改动**：`git status --porcelain` 只有既有未跟踪物
  （`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`）**加上本报告自身**
  `?? modules/mcp_server/docs/reports/REPORT-AUDIT-M4d.md`（审计产物，不是代码改动）。
  门⑥ 的 13 次临时改写在每次实验后都用备份还原，并用 sha256 证明逐字节相同（§C）。
- **观测（非缺陷）**：门③/④ 的 stderr 里有若干 `ERROR: MCPToolRegistry: tool name 'game_get_x' must match …`
  与 `ERROR: [MCP] SceneTree never became available` 等行——它们是 GDR-16 lint 与「裸树」用例**故意**触发的负例输出
  （`Status: SUCCESS!`、`0 failed` 已证），不计入门失败。

## defects

### D1（severity: **high**）`project_set_node_property_across_scenes` 对**活动编辑场景**报成功但没有写入（静默丢失写入）
- **claim**：`force=true` 时，对当前活动编辑场景该工具回 `code=0`、
  `scenes_affected=[{"count":1,"mode":"live_open_scene","nodes":["."],"scene":"res://scenes/good.tscn"},{"count":1,"mode":"offline_saved","nodes":["."],"scene":"res://scenes/side.tscn"}]`、
  顶层 `message="Applied: every closed scene was saved and the active open scene was edited in memory."`，
  但**活动场景根本没有被改**：另一个读工具仍读到旧值，且随后 `editor_save_scene` **把旧值落盘**。
- **evidence**（`e_lost`，全部由本轮自跑；原始响应体 `%TEMP%\audit-m4d\resp\e_lost.003.q_across.resp.json`）：
  1. `P1`：`editor_open_scene(res://scenes/good.tscn)` code 0；读 `.position` = `{"x":1.0,"y":2.0}`；
  2. `P2`：调用 `{type:"Node2D", property:"position", value:{x:3.0,y:4.0}, path_filter:"res://scenes", force:true}`
     → code **0**，`total_scenes=2`，`scenes_affected` 如上（`good.tscn` 被标成 `live_open_scene`）；
  3. `P3`：立刻用**另一个工具** `editor_get_node_properties(path=".", properties=["position"])` 读回 **`{"x":1.0,"y":2.0}`**（旧值）；
  4. `P4`：再 `editor_save_scene` → code 0，磁盘 `res://scenes/good.tscn` 仍是 `position = Vector2(1, 2)`；
  5. `P5`：同一次调用里**关闭的** `res://scenes/side.tscn` 却真的变成 `Vector2(3, 4)`（证明写入路径本身可用）。
- **location**：`modules/mcp_server/tools/project_cross_scene_write.cpp`
  - `:309-317` 计划阶段对所有场景（**包括活动场景**）都用
    `ResourceLoader::load(scene_path, "PackedScene", ResourceLoader::CACHE_MODE_IGNORE)` + `packed->instantiate()`
    得到**游离副本**，`:327/:332/:340` 的匹配与校验都作用在该副本上；
  - `:451-455` 提交阶段对 `mode == "live_open_scene"` **跳过落盘**，只调 `_mark_active_scene_unsaved()`；
    副本随后被丢弃 → 活动场景的**活节点**从未被写到；
  - `:81-86` 的注释声称「with `force` it **edits the live nodes** and marks the scene unsaved」——
    **代码与其自身文档相矛盾**。
- **impact**：调用方拿到「成功 + live_open_scene」的报告，实际是**丢失写入**；工具还把编辑器标成 unsaved，
  于是用户/流程的下一次保存会把**旧值**固化成「已保存」。这正是本里程碑要消灭的「报成功而无效果」类，且会静默丢数据。
- **recommendation**：要么在活动场景上写**活节点**（用 `edited_scene_root()` 的真实节点，并保留
  `mark_scene_as_unsaved`），要么在无法安全写活节点时**诚实拒绝**（`-32000` + suggestion，说明 `force`
  对活动场景不生效），并在 `message` 里不再声称已写入；同时把 `:81-86` 的注释改为与实现一致。
  修完后必须重跑「写活场景 → 另一个工具读回 → 保存 → 文件包含新值」这条链。

### D2（severity: **high**，护栏强度）门⑥ 可被常见拼写绕过，未标注的新收窄点可以静默进入
- **claim**：`check_narrowing_points.py` 只认 `(real_t)`/`(float)`/`Color(`/`Vector2(`/`Vector3(`/`Vector4(`
  六种**字面拼写**；`const real_t x = 1.0e300;`（隐式收窄）、`static_cast<float>(…)`、`::Color(…)`、
  `Vector3{…}`、以及把 `Color` 与 `(` 拆到两行，**全部不被扫描**，门⑥ 仍 exit 0。
  当前树内 30 个点都合规（**无既有缺陷**），但 §22.3/脚本 docstring 的「每个收窄点都必须标注」
  「新增未标注 = 门失败」在拼写层面不成立。
- **evidence**：`c_gate6` C7–C12（见 §C 表）：五个探针 exit **0** 且报告的 `points` 里 **0 个** `audit_probe` 点；
  同一数值写成 `(real_t)` 的对照 exit **1** 且被点名。还原后 sha256 与备份逐字节相同、`git status` 干净。
- **location**：`modules/mcp_server/scripts/check_narrowing_points.py:92-99`（`PATTERNS`）、
  `:241-270`（`_code_only` 逐行、字符串/注释剔除）、`docs/DESIGN-DETAIL.md:706-719`（§22.3 的覆盖声明）。
- **recommendation**：把覆盖声明收窄为「已列举的六种拼写」，并**扩展**扫描（至少加
  `static_cast<\s*(real_t|float)>`、`=\s*<double 字面量>` 赋给 `real_t/float` 的隐式初始化、
  `(?<![\w:>])::Color\s*\(`、`\{\s*` 初始化、以及跨行构造）；更稳的做法是让 CI 直接依赖编译器
  （`-Wconversion`/`-Wfloat-conversion` 或对 `(float)`/`real_t` 赋值做 AST 级检查），
  否则第 5 种形态仍可静默进入。改完必须用本报告的 5 个探针回归（应 exit 1）。

### D3（severity: **medium**）`editor_get_node_properties` 不带 `properties` 时把「检查器分组标签」当成属性输出
- **claim**：全量列举会输出 12 个**并不存在的属性**（`Node`/`Node2D`/`Material`/`Transform`/`Visibility`/
  `Ordering`/`Texture`/`Process`/`Thread Group`/`Auto Translate`/`Editor Description`/
  `Physics Interpolation`/`CanvasItem`），其值为 `null`；更糟的是这些标签与真实属性名**大小写冲突**
  （`Material` 与 `material`），使**大小写不敏感的 JSON 客户端无法解析整个响应**。
- **evidence**：自跑 `editor_get_node_properties{path:Actor}`（不带 `properties`），针对同一响应体，
  本机 PowerShell 5.1 的解析器直接抛错：
  `Cannot convert the JSON string because a dictionary that was converted from the string contains the duplicated keys 'Material' and 'material'.`；
  原始响应正文（未被任何管道加工）位于 `%TEMP%\audit-m4d\resp\probe.009.props_all_actor.resp.json`，
  可见 `"Material":null,"…","material":null,"…"`。
- **location**：`modules/mcp_server/tools/editor_node_read.cpp:192-205`（遍历 `get_property_list()` 时
  只跳过 `_` 前缀与 `script`，未按 `PROPERTY_USAGE_GROUP`/`CATEGORY` 过滤分组标签）。
- **impact**：调用方（尤其 .NET/PowerShell/Java 这类大小写不敏感字典实现的客户端）拿到**无法解析**的响应；
  能解析的客户端也会把这 12 个 `null` 当成「存在但为空」的属性。
- **recommendation**：过滤 `property.usage & PROPERTY_USAGE_GROUP/CATEGORY`（或 `name.is_empty()` 的条目），
  把分组标签放进单独字段；至少不要让标签与属性名在同一 map 里大小写冲突。

### D4（severity: **minor**）未知参数名被静默忽略，拼错的参数会得到「像样的错答案」
- **evidence**：`project_get_settings` 的契约参数是 `prefix`；用 `filter` 调用 → code **0** 且返回 **981** 条设置
  （既没拒绝也没过滤）。另有 `project_set_setting{name:…}` → `-32602 Missing required parameter: key`（这一侧是诚实的）。
- **location**：`tools/project_read_analysis.cpp`（`project_get_settings` 的参数读取）+ 契约 schema 未设
  `additionalProperties:false`。
- **recommendation**：对「未知且非 schema 允许的」参数名返回 `-32602`（可用既有 override 机制改 schema），
  或至少在响应里回显「已忽略的参数」。

### D5（severity: **minor**）`project_set_node_property_across_scenes` 在「零命中」时仍宣称已应用
- **evidence**：`path_filter="res://scenes/good.tscn"`（文件而非目录）→ `total_scenes=0`、`scenes_affected=[]`，
  但 `message="Applied: every closed scene was saved and the active open scene was edited in memory."`，code 0。
- **recommendation**：`total_scenes==0` 时消息显式说明「没有场景匹配 path_filter」，或返回 `-32001` + suggestion。

### D6（severity: **minor**，文档一致性）游戏侧节点路径形态与描述不一致
- **evidence**：`running_game_get_scene_tree` 返回 `path="/root/Main/Actor"`，
  而同族 `running_game_get_node_properties` 的描述写「node_path（相对于场景根节点）」；实测两种写法都能喂回
  （`Actor` 与 `/root/Main/Actor` 都成功），因此不是功能缺陷，只是**描述与线上形态不一致**。
- **recommendation**：描述里说明「返回的是 `/root/...` 形式，且两种形态都接受」。

## unconfirmed

1. **符号链接逃逸**：本机（未提权、无开发者模式）无法创建目录符号链接，
   `res://link_outside/outside_marker.txt` 这条读路径**未端到端验证**（记为 unconfirmed，不作为缺陷）。
2. **双精度构建（`precision=double`）端到端**：本机只构建单精度二进制；D-15 的结论为**源码级 + 单元级**
   （`tool_helpers.cpp:1068-1074` 的编译期常量 + `test_mcp_server.h:13689` 的无条件断言）。
   `DESIGN-DETAIL.md:703` 与 `REPORT-023` §6 已**主动登记**「未做双精度端到端验证」，故这不是隐瞒，而是**已声明的欠账**。
3. **`absolute_path` 的跨机器稳定性**：本机两次独立进程启动的整包响应逐字节相同，但该字段内嵌编辑器布局节点 id
   （`@EditorNode@20539/…`），跨机器/跨布局是否稳定**未验证**（也不应由契约保证）。

## risks

- **R1（高）**：D2 使得「新增收窄点必然被门挡住」这一**结构性保证不成立**——门绿不等于覆盖面完整，
  后续任何批次都可能静默引入第 5 种形态（本轮的 5 个探针就是最小反例）。
- **R2（高）**：D1 的语义是「成功 + 未写入」，且伴随 `mark_scene_as_unsaved()`；若调用方按报告继续 `editor_save_scene`，
  会把**旧值**写成「已保存」的结果，属于静默数据丢失。
- **R3（中）**：D3 的大小写冲突键会让部分主流 JSON 客户端（大小写不敏感字典）**整包解析失败**；
  这类问题在多语言生态里很容易被当成「Godot MCP 偶发坏响应」。
- **R4（低）**：`editor_get_scene_tree` 的 `absolute_path` 字段含每次布局可能变化的编辑器内部 id；
  契约保证的是 `path`，但把整包响应做缓存/去重的调用方会看到无意义抖动。
- **R5（低）**：`rotation_degrees` 这类**派生属性**在读→写→读下有 1 ulp 漂移；
  若将来把「三层等价」做成严格位相等的自动门，会在这里假红（应对派生属性用容差或排除）。

## next_step_recommendation

1. **先修 D1**（high，静默丢失写入）：活动场景要么写活节点，要么诚实拒绝；修完必须重跑
   「写活场景 → 另一工具读回 → `editor_save_scene` → 文件含新值」这条端到端链，并新增回归测试。
2. **再修 D2**（护栏强度）：按 §C 表 5 个探针扩展扫描器/改用工编译器级检查，并把 §22.3 的
   「每个收窄点」表述收窄为「已覆盖的拼写集合」。
3. **D3/D4/D5/D6** 按 severity 排期（D3 优先，属跨客户端可用性）。
4. 三项 `unconfirmed` 中，**双精度端到端**建议单独立项（一次 `precision=double` 重建 + D-15 端到端 + 门重跑），
   符号链接一项在有开发者模式的环境里补验。
5. 上述修改完成后，**由全新子代理再跑一次独立验收**；本报告的脚本与原始响应体全部保留在
   `%TEMP%\audit-m4d\`（`*.results.json`、`resp\`、`logs\`、`gates\`），可直接复用为重跑基线。

## 逐类 verdict

| 类别 | verdict | 依据摘要 |
|---|---|---|
| 全量对等 / scope / override 纪律 | **pass** | 91/91 与 53/53 逐字相等；跨端点 -32601；13 条 override；契约重生成**逐字节相同** |
| 静默错值五形态 | **pass** | 5 形态 + 12 条同族新面全部 `-32602`（或登记的 `WIDE` 槽），四形态证据齐全；⑤ 已分离且风险登记诚实 |
| 门⑥ | **pass（但护栏强度有 high 缺陷 D2）** | 规定动作全对（未标注→exit 1、位移/搬移不假红、删标记→exit 1、索引是标记身份）；**5 种常见拼写可绕过** |
| 顺手性八项（GDR-23/25） | **pass** | E-10/E-1/E-3/§23.4/§23.5/E-9/E-6/G-4/E-2/E-8/G-1/G-3 逐条自跑通过；2 条链 0 次字符串手术 |
| 延迟 / 事务 / 安全 | **fail** | 超时/断连/批量原子性/跨场景全或无/路径逃逸/参数滥用均通过，**但 D1：活动场景报成功却未写入（静默丢失）** |
| 工程门 | **pass** | 六道门全绿（① 5 组 15 例、③ 219/219、④ 1645/1645、⑤ ×2 22/22 清单一致、⑥ exit 0） |
| 端口纪律 | **pass** | 9877 全程 PID 36392；测试与临时端口全部释放；无孤儿；无 git 写、无被跟踪文件改动 |

## 总 verdict

**fail**

理由：硬性要求中「**不得出现『报成功而无效果』**」这一条被 `project_set_node_property_across_scenes`
在**活动编辑场景**上违反（D1，high，可静默丢失写入并误导后续保存）；同时门⑥ 的「新增未标注收窄点必被挡住」
在拼写层面不成立（D2，high，护栏强度），使第 5 种静默错值形态仍可静默进入。
其余全部必核项（对等/scope/override、五形态反例、顺手性八项、延迟与安全、六道门、端口纪律）本轮**均通过**，
且当前树内**没有**发现活着的静默错值点。

## 交付物与可复现性

- 本报告：`modules/mcp_server/docs/reports/REPORT-AUDIT-M4d.md`
- 全部审计脚本与原始证据（未提交、未参与构建）：`%TEMP%\audit-m4d\`
  （`*.ps1`、`*.results.json`、`resp\`（每个响应的原始字节与 sha256）、`bodies\`、`gates\`（六道门日志）、`logs\`）
- 结果汇总：`a_parity 16/16`、`b_silent 56`（23 条由 `b_recheck` 修正，其中 1 条为真缺陷）、`b_recheck 9/9`、
  `c_gate6 30/30`、`d_ergo 31`（2 条由 `d_roundtrip` 重跑）、`d_roundtrip 11/11`、`d_play 16`（2 条由 `d_play_recheck` 重跑）、
  `d_play_recheck 9/9`、`e_security 24`（4 条为脚本判据错误，全部由 `e_recheck` 修正）、`e_recheck 6`、`e_recheck2 5`、
  `e_lost 6/6`、`g_gates`（第一轮因引擎工作目录错而中止，只留下 H0/H0b 两条，已被取代）、`g_gates2 10`、
  `h_fix 12/12`（六道门的最终证据）。
