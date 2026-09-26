# REPORT-AUDIT-B5 — 独立验收：B5 全部 58 工具 + **契约 171/171 收口**（M5 引擎侧）

> 独立验收方：**未参与任何实现**；**未采信**任何 `REPORT-*`（含 `REPORT-AUDIT-M4{,b,c,d,e}` 与 `REPORT-033..036`）
> 与决策者结论。全部结论来自**本轮自己构造并跑出的证据**（任务书 `docs/tasks/TASK-AUDIT-B5.md`）。
> 报告为**新增文件**：未修改任何被跟踪文件、未做任何 git 写操作（分支/索引/历史）、未占用/杀/重启 9877。
> D86：本报告引用他人结论处一律标明其提交锚点并**复测**（见 §9 R4 的独立裁决）。

---

## 0. 开工与基准

| 项 | 值 |
|---|---|
| 分支 / HEAD | `feature/mcp-server-module` / `c7bb936e008f1a70825a6e970f74146744ceba13`（short `c7bb936e00`） |
| 重建 | `modules/mcp_server/scripts/build_local.cmd -Force`（**从 cmd 启动**、`tests=yes`、scons 输出未抑制、未并发），日志 `%TEMP%\audit-b5\build.log`，`EXIT_CODE=0` |
| `--version` | `4.8.dev.custom_build.c7bb936e0` == `git rev-parse --short HEAD` ✔ |
| 端口 | 开工与收尾两次实测 **9877 → PID 36392**（用户 Godot 4.7.1-mono，全程未动）；测试仅 9888/9889，另用 **9890** 跑「无导航数据」变体并已释放；收尾仅剩 9877 一个监听、`audit-b5` 相关进程 **0** 个 |
| 工作树 | 收尾 `git status --porcelain` 仅 4 个既有未跟踪物；`git diff --stat` 为空；`tools_list.renamed.json` 与 `HEAD:` 版本 `git diff` 为空 |
| 临时目录 | `%TEMP%\audit-b5\`（`proj/`、`evidence/`、`gates/`、`gate6/`、`groups/` + 自写脚手架） |

**验收方自己的脚手架（全部自写、纯 ASCII 命令行调用）**

| 文件 | 作用 |
|---|---|
| `mcp.py` / `projects.py` / `serve.py` / `serve3.py` | JSON-RPC 客户端、**自建** scratch 工程（editor/game/navless 三套）、端点管理（`taskkill /T` 收尾，无孤儿） |
| `check_parity.py` | ① 171/171 对等（**自己解析 `name` 字段**、逐字比对、scope 双向、跨端点 `-32601`） |
| `check_contract.py` | ② 契约纪律（AST 读生成器声明数 + 重生成逐字节 + 清空 override 结构化 diff） |
| `check_unregister.py` | ③ 两个 unregister 未注册 |
| `probe_c.py` | ③ B5 三个 fix-first + 30 条不存在目标探针 |
| `probe_early.py` | ③ 早期四个 fix-first + 无导航拒绝 + 主题 `ignored` 语义 |
| `probe_d.py` | ④ 零字符串手术链（AST 机器核对）+ 跨帧观察移动 + §23.4/§23.5 + 主题回读 |
| `probe_g.py` | ⑦ 能力缺失 vs 真实成功 |
| `gate6_adversarial.py` | ⑤ 门⑥ 对抗插入 + 位移不假红 + 逐字节还原 |
| `collect_evidence.py` / `check_evidence_encoding.py` | `curl.exe -s -o` + sha256 证据清单 |
| `adjudicate_s0.py` / `compare_gate5.py` / `summarize.py` | 门② 失败裁决、门⑤ 清单 diff、总汇总 |

**自跑汇总：76 条自建断言，0 条失败**（`result_parity 13` / `result_contract 6` / `result_fixfirst 21` /
`result_early 9` / `result_ergonomics 7` / `result_android 6` / `result_unregister 4` / `result_gate6_adversarial 10`）。

---

## 1. verdict（按任务书的八类）

| 类 | verdict | 一句话依据 |
|---|---|---|
| **① 171/171 对等** | **pass** | 自解析 9888 `name` 148 + 9889 `name` 69，**并集恰为契约 171**（missing=0/extra=0）；217 组 `(name, description, inputSchema)` **逐字相等**；scope 双向差集为空（editor 148/148、game 69/69）；**125** 条跨端点调用全部 `-32601` 且无 result；组清单四种模式 exit 0 |
| **② 契约纪律** | **pass** | 生成器 AST 声明 **11 description + 7 inputSchema = 18**，跟踪文件 `_meta.overrides` = **18** 且集合逐对相等；生成器重生成到临时文件 **110770 字节逐字节相同**（sha256 `c844ec8a…`）；清空 override 后结构化 diff **只**差那 18 对字段 + `_meta.overrides` |
| **③ fix-first 与诚实性** | **pass** | 映射声明的 **7 个 fix-first 全部自己复现**（4 早期 + 3 B5），3 个 B5 的含写→读互验/全成功或全回滚/另一工具证明产出的真证据；**2 个 unregister 未注册**；**30 条不存在目标探针覆盖 29 个不同 B5 工具**全部明确报错且带可读建议 |
| **④ 顺手性** | **pass** | 自跑主题链 6 步 + 移动链 3 步，**AST 机器核对 22 个工具调用实参表达式 0 处字符串手术**；`running_game_move_player_to_target` **真的在移动**（24 个互异采样、最大单步 20.7 vs 总位移 426.2）；§23.4 往返 **10/10**；§23.5 三形态 + 两边界全符；主题写全部回读核实 |
| **⑤ 门⑥ 对抗** | **pass** | 基线 exit 0 + `--coverage` exit 0（17 种拼写 + **未覆盖边界被显式打印**）+ 探针 **101/101** exit 0；**自己插** `(real_t)`/`static_cast<float>`/`Color{…}` 各 exit **1**，只插空行/空白/注释 exit **0**（不假红），标注但未登记仍 exit 1，**逐字节还原**（sha256 前后同一、`git status` 不变） |
| **⑥ 工程门** | **pass** | 门① **5 组 × 3/3** exit 0；门③ `259/259`（15605 断言）0 failed；门④ `1685/1685`（439887 断言）0 failed；门⑤ `22/22` ×2 且 PASS 清单**逐项+顺序一致**；门② 4 个证据脚本重跑（③ 见 R4 裁决） |
| **⑦ 端口** | **pass** | 9877 前后同为 PID 36392；测试口 9888/9889/9890 收尾全部释放；`audit-b5` 相关进程 0；无孤儿 godot |
| **⑧ 能力缺失声明** | **pass** | `project_get_export_info`/`project_list_export_presets` 拿到**真实成功**（本机确有 Android 预设）；Android 三工具**没有伪造成功/假设备**，其「能力缺失」证据与**本机实测**（无 adb、无 SDK 目录、无模板）一致，并与真实成功分支分列 |

**总 verdict：pass。** 3 条 low 记录（§9 D1/D2 为被测实现的低危项；D3 是本验收方自身的方法学更正）与
5 条风险（§9 R1–R5）均不构成任何一类的闭合失败。

---

## 2. ① 171/171 全量对等（核心）

### 2.1 名字集合：**自己解析 `name` 字段**（不使用任何文本包含判断）

`curl.exe -s -o` 落盘的原始响应：

| 端点 | 字节 | sha256 | `name` 条数 | 唯一 |
|---|---|---|---|---|
| 9888（editor） | 43186 | `60c0af5cb43a06a8674c82eb8974c3f9d901e5403bf7b8ac1413741f9789532f` | 148 | 148 |
| 9889（game） | 23359 | `30255ad8a6b95d8d70e463c38acfd33d04df334d6f5babb7d6cc0a303008f57d` | 69 | 69 |

* **并集 = 171，missing = 0，extra = 0**（`A2_union_equals_contract`）。
* 契约自身：171 条、名字唯一 171（`A0_contract_count` / `A0_contract_unique`）。
* 请求体与响应体均落盘（`%TEMP%\audit-b5\evidence\*.req.json|*.res.json` + `manifest.json` 含每个文件的
  `sha256` 与请求体 `sha256`）。

### 2.2 逐字相等

对**两端点各自可见**的每条工具，比较 `name` / `description` / `inputSchema`（schema 走键序无关的规范
化后比较）：**217 组三元组、mismatches = 0**（`A4_verbatim`）。其中 schema 的规范化比较与 `_meta` 无关，
不含任何 override 例外。

### 2.3 scope 双向零泄漏

以 `docs/tool-rename-map.json` 的 `scope`（171 个契约名各一条；非 merge 条目 173 = 171 + 2 个
`unregister_until_implemented`，见 `A0_scope_entries`）推导：

| 端点 | 期望 | 实况 | live-only | expected-only |
|---|---|---|---|---|
| 9888 | 148 | 148 | 0 | 0 |
| 9889 | 69 | 69 | 0 | 0 |

共享 46 / 仅编辑器 102 / 仅游戏 23（102+23+46 = 171）。门① 的 5 次运行也独立打印同一组数字
（`editor-only=102 game-only=23 both/shared=46`）。

### 2.4 跨端点 `-32601` 且不执行

**125** 条调用：102 条 editor-scope 工具打 9889、23 条 game-scope 工具打 9888 —— 全部返回
`error.code = -32601` 且**响应中不含 `result`**（`A5_cross_endpoint_-32601`；其中两条原始响应
`cross_9889_editor_tool` sha256 `3803d8da…`、`cross_9888_game_tool` sha256 `ce9e1710…`，各 106 字节）。

### 2.5 机器校验

| 命令 | exit |
|---|---|
| `check_tool_groups.py`（无参数 = B1 路径） | 0 |
| `check_tool_groups.py --batch B2 \| B3 \| B4 \| B5` | 0 / 0 / 0 / 0 |
| `check_tool_groups.py --check-completeness` | 0 |
| `check_tool_groups.py --batch B1` | **1**（见 §9 D1） |

`--check-completeness` 原文：`契约 171 = B1/B2 66 + B3+B4+B5 105`，`B3+B4+B5 = 40+7+58 = 105 各恰好一次`、
两两不相交、与 B1/B2 不相交、`missing=0, foreign=0`，且 2 个 unregister 名字确实不在契约里。
组文件 sha256：B2 `14eba000…`、B3 `d3422a6e…`、B4 `d95d7d9e…`、B5 `85bb783e…`。

---

## 3. ② 契约纪律（override 必须可核对）

1. **声明数（读源码）**：以 AST 读 `scripts/gen_renamed_contract.py` 的字面量字典 —
   `DESCRIPTION_OVERRIDES` 11 条、`SCHEMA_OVERRIDES` 7 条，**合计 18**。
2. **跟踪文件**：`_meta.overrides` = **18** 条，每条都带 `kind/old_name/mode/reason`，`reason` 非空；
   记录集合与第 1 步声明集合**逐对相等**（`(kind, old_name)` 双向）。
   模式分布：description 10×append + 1×replace（`analyze_signal_flow`）；inputSchema 7×replace。
3. **无手改（自己重生成）**：用**仓库里的生成器**（`--out` 指到临时文件，默认入口参数不变）重生成：

   | | 字节 | sha256 |
   |---|---|---|
   | 跟踪文件 | 110770 | `c844ec8af9ef00d2e6ec7008c9806b3e2b16757e78794d3ccca0704edf844256` |
   | 我重生成 | 110770 | `c844ec8af9ef00d2e6ec7008c9806b3e2b16757e78794d3ccca0704edf844256` |

   **逐字节相同**（`B5_regenerate_byte_identical`，exit 0）。生成器自报：输入 174 → 输出 171、
   merge 1（`get_editor_performance -> get_performance_monitors`）、unregister 2、overrides 18、
   旧夹具 sha256 `8f8051c4…`、映射 sha256 `2f552719…`。
4. **结构化 diff**：把生成器实例的两张 override 表在**内存里置空**后重生成基线
   （sha256 `73cfd8de…`，exit 0），与跟踪文件逐工具逐字段比较：

   * `description` 差异 **11** 条 = 声明的 11 个 `old_name` 映射到的新名，**完全相等**；
   * `inputSchema` 差异 **7** 条 = 声明的 7 个，**完全相等**；
   * `name` 及其他字段差异 **0** 条；`_meta` 唯一不同的键 = `["overrides"]`。

   即：**跟踪契约 = 机械生成结果 + 恰好那 18 条已登记 override**，没有第二处改动。

---

## 4. ③ 诚实性：7 个 fix-first + 2 个 unregister + 不存在目标

映射（`tool-rename-map.json`）声明的 `fix_implementation_first` **恰好 7 个**，本轮**全部**自建证据；
`unregister_until_implemented` **恰好 2 个**。

### 4.1 B5 的 3 个（数据破坏/假成功级）

**(a) `editor_set_tilemap_cell` —— 写真的落进去，读族能读回**

自建 scratch 场景的 `TileMapLayer`「Tiles」带一个 `TileSetScenesCollectionSource`（source 0，1 个 tile）：

* 初始 `editor_get_tilemap_info` → `cell_count=0`、`sources=[{source_id:0,tile_count:1}]`（`C1`/`C1b`）。
* 写 `(2,3) source 0 atlas(0,0)` → `applied=true, empty=false, source_id=0`；
  **三个读者独立确认**：`editor_get_tilemap_cell(2,3)` → `source_id=0, atlas={0,0}, empty=false`；
  `editor_get_tilemap_used_cells` → `count=2` 且列出的 cells 含 `(2,3)`；
  `editor_get_tilemap_info` → `cell_count=2`（`C2`）。
* 负坐标 `(-4,-7)` 往返成功（`C3`）；`source_id=-1` 是**显式清除**且读回 `empty=true`（`C4`）——
  即迁移源那套「单参 `set_cell` = 擦除形状」不再出现：单参写把 `atlas_coords` 缺省成 `(0,0)` **真写入**，
  擦除必须显式表达。
* 拒绝路径：未知 source `999` → `-32602`「...has no source 999; it has: 0」；source 无 tile 的 atlas `(7,7)`
  → `-32602`「...has no tile at atlas_coords (7, 7); it has: (0, 0)」；未知节点 → `-32001` + 建议（`C5`/`C6`/`C7`）。
* 三次拒绝后 `used_cells` 仍是 2 —— **拒绝不产生写入**（`C8`）。

**(b) `editor_set_tilemap_cells_in_rect` —— 全成功或全回滚**

* `3×4` 矩形 → `filled=12, verified=12, restored=false`，`used_cells` 2 → 14（delta 恰 12）（`C9`）。
* **故意坏的中间元素**：atlas `(9,9)`（source 里没有）→ 整调用 `-32602`，`used_cells` **仍是 14**，
  且被拒矩形的第一个格子 `(20,20)` 读回 `empty=true`（`C10`）；
  未知 source `777` 同样整调用拒绝、计数不变（`C11`）。
* `editor_remove_all_tilemap_cells` → `removed=14, remaining=0`，读者随即 `count=0`（`C12`）。

**(c) `editor_bake_navigation_mesh` —— 另一工具证明真的产出**

* 烘焙前：`editor_get_navigation_info` → `polygon_count=0, baked=false`（`C13`）。
* `editor_bake_navigation_mesh(Region)`（延迟通道）→ `polygon_count=2, before_polygon_count=0, changed=true,
  bake_signalled_done=true, verify_tool=editor_get_navigation_info`（`C14`）。
* **另两个独立见证**：`editor_get_navigation_info` 复核 `polygon_count=2, baked=true`（与工具自报一致）；
  `editor_execute_gdscript` 直接问引擎 → `{polygons:2, vertices:4, map_regions:1, map_iteration:3}`（`C15`）。
* 诚实拒绝：对非导航节点的 `Mesh` → `-32602`（消息点明 `MeshInstance3D` 不是 NavigationRegion）；
  未知节点 → `-32001` + 建议（`C16`/`C17`）。
* **无导航数据**：在只有 `NavigationMesh` 子资源、**没有源几何**的 region 上烘焙 → 返回
  `baked=false, changed=false, bake_signalled_done=true` + `message`「烘焙跑了但没有多边形，检查
  geometry_parsed_geometry_type/…」——**明确否认成功**，不是假成功（原文见本报告证据文件）。

### 4.2 早期 4 个（自己构造的活证据）

**(a) `editor_remove_output_log`（旧 `clear_output`）**：先用 `editor_execute_gdscript` 打印两行带标记
文本，`editor_get_output_log(filter)` 读到 `count=2` 且含标记（`CE1`）；调用后
`{cleared:true, log_was_empty:false, log_is_empty:true}`，同一读者再读 `count=0`、标记消失（`CE2`）。
（迁移源当年打印约 50 个空行并恒回 `{cleared:true}`，本轮证据显示已改为**测量+真清**。）

**(b) `editor_disconnect_signal`（旧 `disconnect_signal`）**：用 `editor_connect_signal` 建**两条**连接
`SigA.renamed -> SigB.queue_free` 与 `-> SigC.queue_free`，引擎自身 `get_signal_connection_list('renamed')`
读回 `['SigB','SigC']`；调用 `editor_disconnect_signal(source_path=SigA, signal=renamed, target_path=SigB,
method=queue_free)` 后再读 → **`['SigC']`**（`CE3`）。即**只断命名目标**；迁移源那套「用场景根当 Callable」
会两条都不断。

**(c) `editor_set_auto_dismiss_dialogs`（旧 `set_auto_dismiss`）**：`enabled=true` → `-32000 Not implemented`
+ 建议点名真实旋钮（`AcceptDialog.hide_on_ok`、`interface/editor/appearance/accept_dialog_cancel_ok_buttons`）；
`enabled="yes"` 与缺参 → `-32602`（`CE4`）。响应中**没有** `auto_dismiss: true` 之类回显——正是被移除的假成功形状。

**(d) `editor_get_test_report`（旧 `get_test_report`）**：跨进程桥接
（`user://mcp_test_report.json`；本机 `%APPDATA%\audit-b5-shared\mcp_test_report.json`）：

* 游戏端点用 `running_game_assert_node_state` 记录**两条真实断言**（一条 `passed=true`、一条 `passed=false`）；
* 编辑器端点 `editor_get_test_report` → `source=game_process_file, report_file_present=true,
  total=2, passed=1, failed=1, all_passed=false`，且**桥接文件在磁盘上真实存在**（`CE5`）；
* 断言之前：`no_results=true, report_file_present=false, total=0`——**不编造 total**；
* `clear:true` → `cleared=["editor_process","game_process_file"]`（真的清掉的**两侧**）、桥接文件消失、
  再读 `no_results=true`（`CE6`）。契约里 `clear` 的默认值是 **false**（纯读取），与实测一致。

### 4.3 两个 unregister 仍未注册

| 旧名 | 新名 | 契约内 | 端点可见 | `register_tool(...)` 调用点 |
|---|---|---|---|---|
| `navigate_to` | `running_game_move_player_to_target_via_navigation` | 否 | 无 | 无（`git grep -F` 跟踪文件） |
| `export_project` | `project_export_game` | 否 | 无 | 无 |

`check_tool_groups.py --check-completeness` 独立断言这两名**不在 171 契约里**（因此不参与 `171-2` 双重扣减）。

### 4.4 「不存在目标」必须明确报错（≥10 个 B5 工具）

**30 条探针、29 个不同 B5 工具**（我在 `probe_c.py` 里逐条列出并在 `C18` 上机器求和），覆盖
未知节点 / 未知瓦片源 / 未知 atlas / 未知 shader uniform / 不存在的 shader 与 theme 路径 /
不存在的动画与粒子预设 / 不存在的 audio bus / 不存在的 player 与 target 节点：

* **全部**返回显式 JSON-RPC 错误（`-32001` 或 `-32602`）且 `message` 可读；
  编辑器侧全部附带 `data.suggestion`（含建议调用哪个工具去列举实际可用者）。
* 抽两条原文：`editor_set_tilemap_cell` 未知节点 → `-32001 Node 'Nope' in the edited scene not found`
  + 建议「`node_path` 是相对编辑场景根（'.' 是根本身）；用 `editor_get_scene_tree` 列出现有节点」；
  `editor_set_shader_param` 未声明 uniform → `-32001 Shader parameter 'no_such_uniform' of
  'res://audit_probe.gdshader' not found` + 建议「该 shader 声明了：'albedo'」。
* 额外两条**明确裁定为「不是缺陷」**的：
  - 主题项名是**开放的 name→value 映射**（`Theme::set_color` 会新建条目），因此
    `project_set_theme_color(color_name="no_such_color")` 成功并**被读者读到新条目** —— 这是引擎语义，
    不是「未知主题项」；真正未知的资源路径（`res://no_such_theme.tres`）→ `-32001` + 建议。
  - `editor_set_shader_material` 的契约默认 `material_slot="material"`：在 `MeshInstance3D` 上该槽不存在
    → `-32602` 并**列出该节点真实的槽**（`material_override`/`material_overlay`/
    `surface_material_override/0`）；在**拥有 `material` 属性的 Control** 上缺省调用成功
    `material_slot="material"`（`C20`）。默认值随节点类型而变，错误诚实且可诊断 —— 记为风险 R1 而非缺陷。

---

## 5. ④ 顺手性（GDR-25）

### 5.1 零字符串手术链（自跑，且**机器核对调用方字符串处理 = 0**）

* **主题链（6 步）**：`project_create_theme → project_set_theme_color → project_set_theme_constant →
  project_set_theme_font_size → project_set_theme_stylebox → project_get_theme_info`；每一步的路径/条目名
  都取上一步响应自己的字段（`path` / `theme_path` / `color_name` / `constant_name` / `font_size_name` /
  `stylebox_name`）。读者最终同时看到 `colors.Button.font_color`、
  `constants.Button.font_color=7`、`font_sizes.Button.font_color=19`、`styleboxes.Panel.<name>`（`D1`）。
* **移动链（3 步，游戏端点）**：`running_game_get_scene_tree` → 从树里取 `path` 字段得到玩家
  `/root/Main/Player` 与目标 `/root/Main/Goal` → `running_game_move_player_to_target(player_path=<上一步>,
  target=<上一步>)` → `running_game_get_node_properties` 读到与工具自报**完全相同**的终点
  `(449.852111816406, 356.134063720703)`（`D2`）。
* **机器核对**：对两个链函数的**每一个工具调用实参表达式**（22 个）做 AST 遍历，禁止嵌套调用
  （`.get/.split/.format` 之类）、f-string、`BinOp` 拼接、推导式 —— **offenders = 0**；脚本自身的
  字符串手术计数器 `STRING_OPS = 0`（`D3`）。链里唯一对响应的“处理”是**相等比较**（`find_node/find_named`
  用 `type`/`name` 字段命中后取 `path`），不切片、不改写。

### 5.2 `running_game_move_player_to_target` **真的在移动**（不是瞬移）

先把玩家复位到 `(40,200)`，再**并发**发起工具调用，同时用**另一个工具**
`running_game_get_node_properties` 每约 50 ms 跨帧取一次 `position`：

* 采到 **24 个位置样本、24 个互异值**；首 `(40.0, 200.0)`，末 `(438.253, 351.715)`；
  路径上**互异中间位置 24 个**；**最大单步位移 20.687**，而总位移 **426.172**
  —— 若是瞬移，只会有“一个等于全程的跳变”（`D4`）。
* 工具自报 `reached=true`、`path_source=navigation_agent`、`position_sample_count=23`、
  `final_position={x:449.852111816406, y:356.134063720703}`；随后**独立读**同一节点的 `position` 与自报终点
  **完全相同**。
* 无导航数据时（第三个工程，只有 Player/Goal、**没有 NavigationRegion**）→ `-32000`
  「The navigation map of player '/root/Main/Player' has no region: there is no navigation data to follow,
  so this tool refuses instead of moving the player straight through the world」+ 建议（`CE7`）。

### 5.3 §23.4 读回↔写回双向闭合（抽样 10 项，≥8）

每条都断言**三层等价**：`code=0` → `new_value` 与首次读回**结构化相等** → **再读**仍相等。

| 项 | 类型/形状 | 落点 | 结果 |
|---|---|---|---|
| 1 | `Vector2` `{x,y}` | `UILayer/Panel.position` | ✔ |
| 2 | `Vector3` `{x,y,z}` | `Mesh.position` | ✔ |
| 3 | `Color` `{r,g,b,a}` | `UILayer/Panel.modulate` | ✔ |
| 4 | 标量 `float` | `UILayer/Panel.rotation` | ✔ |
| 5 | `Rect2` `{x,y,width,height}` | `Sprite.region_rect` | ✔ |
| 6 | `PackedVector2Array`（元素对象形态） | `Line.points` | ✔ |
| 7 | `PackedColorArray` | `Gradient.colors` | ✔ |
| 8 | `PackedFloat32Array` | `Gradient.offsets` | ✔ |
| 9 | `PackedInt32Array` | `ArrayOccluder3D.indices` | ✔ |
| 10 | `PackedByteArray` | `AudioStreamWAV.data` | ✔ |

`10/10`（`D5_roundtrips`）。**分量形态的教训**（顺手性证据）：`Line2D.points` 用
`[[0,0],[10,20]]`（数组套数组）会被 `-32602` 拒绝并**给出正确写法**「Send the property type's own shape:
a JSON object naming its components for a vector/color」，改成 `[{"x":0,"y":0},{"x":10,"y":20}]` 即成功
—— 错误信息足以让调用方一次纠正。

### 5.4 §23.5 `OBJECT` 三形态 + 边界

| 写回形态 | 结果 |
|---|---|
| 对象 `{"type":"StandardMaterial3D","path":"res://audit_obj_mat.tres"}` | `code=0`；读回**同形** `{path,type}` |
| 字符串 `"res://audit_obj_mat.tres"` | `code=0`；读回同形 |
| `null` | `code=0`；读回 **`null`**（不是 `{}`） |
| `{}`（空对象） | `-32602`（信息不足，不当成清除） |
| 对象指向不可加载路径 | `-32001` `Resource 'res://no_such_mat.tres' named by parameter 'value' not found` |

（`D6_object_three_forms`）

### 5.5 主题写必须回读核实（引擎归一化/夹取 → `ignored` 语义）

* 6 步主题链的每个写入都被 `project_get_theme_info` **逐值回读**：`font_color` 精确为
  `{r:0.125,g:0.25,b:0.5,a:1.0}`、`separation=9`、`title_size=21`、`panel` stylebox 存在（`D7`）。
* **非正字号**（D90 声称「进 `ignored` 并标 `font_size_readable:false`」——**我复测成立**）：
  `size=0` → `properties_set=[]`、`ignored={title_size:{requested:0, stored:null, reason:"…只答正数…用 >0 的尺寸"}}`、
  `font_size_readable=false`；`size=-5` 同形（`CE8`）。
* 读者侧的 `font_sizes_stored_not_readable` **确实会工作**：我**手写**一个真正持有
  `Button/font_sizes/hand_zero = 0`、`hand_neg = -5` 的主题文件 → 读者答
  `font_sizes_stored_not_readable=["hand_neg","hand_zero"]` 且**不**把它们放进 `font_sizes`
  （只列 `hand_ok=24`）（`CE9`）。经写入器保存的主题之所以看不到该字段，是因为保存经引擎的
  `_get` → `get_font_size` 会把 `<=0` **归一化成回退字号**（实测落盘 `= 16`）——见风险 R2。

---

## 6. ⑤ 门⑥ 三段式 + **对抗**

### 6.1 三段（我自己跑的、未抑制输出）

| 命令 | exit | 关键原文 |
|---|---|---|
| `python check_narrowing_points.py` | **0** | `scanned == pinned`，无未标注/未登记/陈旧条目 |
| `python check_narrowing_points.py --coverage` | **0** | 打印 **17 种已声明拼写**（`cast_real_t`…`dbl_cast_into_float`）+ **未覆盖边界**（运行时隐式 double→real_t、表达式推导出的越界、整数收窄、**另一个翻译单元**里的 typedef 别名、`tools/**` 之外）+ `guarantee_position`：三腿之一 |
| `powershell … mcp031_gate6_coverage_probes.ps1` | **0** | `101/101 checks passed`，含 `B1b_worktree_clean_of_probes`（探针文件 `git status --porcelain` 为空） |
| `python check_narrowing_points.py --json` | **0** | `unlisted: []` |

§22.3b 规则 6 要求的「覆盖集合**与**未覆盖边界都被打印」**成立**（`--coverage` 两段都在）。

### 6.2 对抗插入（我自己的探针，**不使用任何 git 写命令还原**）

对真实 B5 文件 `modules/mcp_server/tools/editor_tilemap_write.cpp` 逐个插入（基线 sha256
`96081431f599df47e35154d552d914c3333bcbda7662472f9e8dec49f162e849`）：

| 探针 | 内容 | 期望 | 实测 |
|---|---|---|---|
| E16-1 | `const real_t x = (real_t)1.0e300;`（无标注） | exit 1 | **1**，报告 `[UNLISTED] tools/editor_tilemap_write.cpp:72 UNMARKED` |
| E16-2 | `const float x = static_cast<float>(1.0e300);`（无标注） | exit 1 | **1** |
| E16-3 | `const Color c = Color{1.0e300, 0.0, 0.0, 1.0};`（无标注） | exit 1 | **1** |
| E16-4 | 只插一个空行 | exit 0（**不假红**） | **0** |
| E16-5 | 只插一个空白行（`\t`） | exit 0 | **0** |
| E16-6 | 只插一条注释 | exit 0 | **0** |
| E16-7 | 加了 `// MCP-NARROWING: AUDIT-PROBE` 但该 marker 未登记进 `PINNED` | exit 1 | **1** |
| E17 | **从 `%TEMP%` 的私有备份逐字节还原** | sha256 相同、`git status` 不变 | sha256 前后**相同**；`git status --porcelain` 前后一致；随后门⑥ 再跑一次仍 **0** |

---

## 7. ⑥ 工程门与端口

| 门 | 命令 | 结果 |
|---|---|---|
| ① | `check_contract_subset.ps1 -Group <组>` × **5 组**：`project_read_template`（B1）、`editor_tilemap_write`、`editor_navigation_write`、`project_theme_write`、`os_android_write`（B5） | **每组 3/3 PASS、exit 0**；每次都打印 `implemented_union=148 tools (editor) / 69 tools (game)`、`scope: editor-only=102 game-only=23 both/shared=46`、`guard_user_port_9877` PASS |
| ② | 重跑 4 个实现期证据脚本 | `mcp033` exit **0**；`mcp036` exit **0**；`mcp034` exit 1（109/114）、`mcp035` exit 1（66/67）→ **裁决为脚本侧陈旧锚点，非实现回归**（§9 R4） |
| ③ | `--headless --test --test-case="[MCPServer]*"` | `259 cases | 259 passed | 0 failed`、`15605 assertions | 15605 passed | 0 failed`、exit **0** |
| ④ | `--headless --test` | `1685 cases | 1685 passed | 0 failed`、`439887 assertions | 439887 passed`、exit **0** |
| ⑤ | `accept_m1.ps1` **×2** | 两次都 `22/22 cases passed`、exit **0**；两次 **PASS 清单逐项且顺序一致**（22 条，`set difference = []`，含 `case8_concurrent_100`、`case20_tools_list_cross_process_restart`、`case14_port_occupied`、`guard_user_port_9877`） |
| ⑥ | 见 §6 | exit 0 / 0 / 101-101；自造对抗全红、位移不假红、逐字节还原 |

**端口纪律**：开工/收尾 `9877 → PID 36392`；全流程只用 9888/9889（另用 9890 跑 navless 变体，收尾释放）；
收尾 `Get-NetTCPConnection` 在 9877/9888/9889/9890 上只剩 9877；`CommandLine` 含 `audit-b5` 的 godot/python 进程 = **0**。

---

## 8. ⑦ 能力缺失 vs 真实成功（Android/export，**分列**）

**本机实测（我自己跑的宿主事实）**：`adb` 不在 PATH；候选 SDK 目录
（`%LOCALAPPDATA%\Android\Sdk`、`ANDROID_HOME`、`ANDROID_SDK_ROOT`、`C:\Android\android-sdk`、
`C:\Users\Public\Android\Sdk`）**全部不存在**；`ANDROID_HOME`/`ANDROID_SDK_ROOT` 未设置；
`JAVA_HOME` 存在（`jdk-17.0.12`）。项目里**确实**有一个 Android 导出预设
（我预先写入 `export_presets.cfg`，sha256 记录在证据目录）。

**(A) 真实成功分支（`project_*_read` 家族）**

* `project_get_export_info` → `presets_file_present=true, preset_count=1, presets_source="editor_export",
  export_platform_count=7, platforms=[{platform:"Android", preset_count:1}]`（9888，`G1`；原始响应 curl
  sha256 `5e4f952e…`）。
* `project_list_export_presets` → `count=1`，条目含 `name="Android"`、
  `android_package_name="com.example.auditb5"`、`export_path="build/audit.apk"`（sha256 `c3262cf6…`）。
* `project_get_android_preset_info(preset_name="Android")` → 预设可读（名字/包名/自定义特性真实回显），
  同时 `export_capability.checked=true, can_export=false`，`error` 是**引擎自己**的
  `EditorExportPlatform::can_export` 文案（缺导出模板 + 缺 SDK `platform-tools`），
  `environment` 列出 `android_sdk_ready=false`、`missing=[android_sdk, adb]`（sha256 `6f108f5d…`）。

**(B) 能力缺失分支（`os_*` / android 写侧）—— 无伪造成功、无假设备**

* `os_list_android_devices` → `-32000`「Could not run 'adb': Can't fork」+ `data.suggestion`，
  **不是** `{count:0}`（即没有把「跑不起来」说成「没有设备」）；与宿主「无 adb」一致（`G3`，sha256 `4e37606e…`）。
* `os_deploy_to_android_device(preset_name="Android")` → `-32000` + `data.suggestion`（装模板/配 SDK/再调用），
  `data.missing` 列出 three 项；且收尾时 `res://build/audit.apk` **不存在** —— 没有产出任何它没做的事（`G4`，sha256 `eeef9d2c…`）。
* **同一工具在游戏端点上的诚实空**：9889（游戏工程的 `user://` 项目里确实没有 `export_presets.cfg`）
  `project_get_export_info` → `presets_file_present=false, preset_count=0` + `message` +
  `unavailable=[export_presets, editor_export]`（**不是**错误、也**不是**编造的预设）（`G5`，sha256 `0b19605e…`）。
* 未知预设名 → `-32001 Export preset 'NoSuchPreset' not found`（`G6`）。
* 原始响应均经 `curl.exe -s -o` 落盘并算 sha256；`python check_evidence_encoding.py` 复核这些文件
  **是合法 UTF-8**，引擎自带的中文错误文案（如「预设路径中未找到导出模板：…」）**码点完整**
  （`U+9884 U+8DEF …`，无替换字符）—— 控制台里看到的「乱码」是本机终端代码页的显示问题，**不是**模块的编码缺陷。

---

## 9. defects / unconfirmed / risks

### defects（3 条，全部 low，均不阻塞收口）

**D1（low，接口/文档不一致）`check_tool_groups.py --batch B1` 自相矛盾。**
脚本的 usage 字符串写 `[--batch B1|B2|B3|B4|B5]`，但其分派把 B1 判为 `unknown batch` 并 `exit 1`
（实测：`--batch B1` → exit **1** + `usage: … (unknown batch: B1)`）。B1 的不变式实际由**无参数路径**执行
（exit 0）。本验收任务书要求「`--batch B1|B2|B3|B4|B5` 全部 exit 0」，该拼写**无法**满足。
建议：把 usage 里 B1 改为「无参数」，或让 `--batch B1` 等价于无参数路径。
**影响面**：仅命令行可用性，不影响任何不变式强度（B1 的不变式我已用无参数路径验到 exit 0）。

**D2（low，§20.6 `ignored` 语义未落地；**先于 B5 的既有实现**，`project_edit_resource` 非 B5 工具）**
规范 §20.6 要求：`project_create_resource`/`project_edit_resource` 必须以 `changed:{prop:{old,new}}` 报真实结果，
引擎**夹取或忽略**的属性**不得**列为已设置、**必须**列入 `ignored` 并给 `requested`/`stored`/`reason`。实测：

* 引擎把 `Curve.min_value=5.0` 夹成 `0.990000009536743`，工具把它列进 **`changed`**（`new=0.99`），
  **没有任何 `ignored` 条目**（`ignored` 字段在该响应里不存在）；
* 完全**未知的属性名**（`no_such_property`）→ 返回 `{"changed":{},"message":"No properties were changed"}`
  （**成功形状**），既不报错也不在 `ignored` 里点名该参数。

诚实的一面是它没有把请求值谎报为已写入（`min_value` 报的是回读真值 0.99）；缺陷在于**分类缺失**，
调用方无法从响应区分「这个参数我没动」与「这个参数不存在」。建议：未知键 → `-32602` 或写入 `ignored`
（带 `requested/stored/reason`）；被夹取值 → 进 `ignored`。

**D3（low，本验收方方法学瑕疵，记录以免误读）我最初的四条断言是错的**，已在报告外更正并重跑：
`editor_get_tilemap_info.sources`（不是 `source_ids`）、`editor_get_test_report.clear` 默认 **false**
（不是 true）、跨进程桥接必须两个进程**共享 `user://`**（我最初用了两个不同工程名）、以及用
`check_tool_groups.py --batch B1` 去断言 B1。它们**不是**被测实现的缺陷；列出它们是 D86 纪律的一部分
（结论必须可追溯、错误要撤回而不是悄悄改口径）。

### unconfirmed

1. **单精度之外的构建**：本机只构建单精度二进制，`ValueSlot::FLOAT32` 在 `precision=double` 下的行为
   仍是**源码级 + 单元级**结论（§22.2 已登记），本轮未做端到端双精度验证。
2. **Android 成功分支未被证明可达**：本机无 SDK/模板/设备，`os_deploy_to_android_device` 与
   `project_get_android_preset_info.can_export` 只拿到「能力缺失」证据；「有设备时真的能装」**未验证**。
3. **§23.4 完整矩阵**：规范列 19 项×两端点，本轮按任务书抽样 **10 项**（含 packed 与 object），
   未逐项重跑 19×2；`Transform2D/Transform3D`、`Basis`、`Plane`、`Projection`、`AABB` 仍**无工具读回**（登记欠账）。
4. **B5 其余工具的不存在目标**：抽查覆盖 **29/58** 个 B5 工具（30 条探针），其余 29 个未逐一构造。
5. **`editor_get_test_report` 的编辑器内存累加器**：本轮只验证了「文件桥接 + clear 两侧」，
   编辑器进程内累加器（editor-scope 工具写入它的路径）未构造成功案例。

### risks

**R1（low）`editor_set_shader_material.material_slot` 的契约默认值依赖节点类型。**
契约 `default="material"`；在 `MeshInstance3D`（无 `material` 槽）上省略该参数 → `-32602`。错误消息
把该节点真实槽名列全，属诚实可诊断；但**按契约默认值机械填参的客户端会在 3D mesh 上直接失败**。
建议（若后续收紧）：把默认值改成按节点类型解析，或让错误消息显式提示「默认值 'material' 仅适用于 CanvasItem」。

**R2（low）非正字号经保存后被引擎归一化为回退值，读者看不出原因。**
`project_set_theme_font_size(size=0)` 写入器答 `ignored{requested:0, stored:null, …}`、
`font_size_readable=false`（诚实）；但保存走引擎 `_get → get_font_size`，**落盘值实际是回退字号 16**，
随后 `project_get_theme_info` 把 `zero_size=16` 列进 `font_sizes`（且 `font_sizes_stored_not_readable` 为空）。
即「读者眼中 16 是被设置的」与「写入器说这个值读不回来」两条信息**分散在两个工具里**。建议：读者对
「值等于引擎回退字号」的条目给出可选项标注（或在 `saved` 侧点明落盘值）。

**R3（medium，继承 D86 R1）门⑥ 仍是**有限拼写集合**的保证。**
我插入的 3 种拼写全被抓住、位移与控制组都不假红；但 `--coverage` 打印的未覆盖边界**依旧存在**
（运行时隐式 `double → real_t`、表达式推导出的越界、整数收窄、另一 TU 的 typedef 别名、`tools/**` 之外）。
因此门⑥ 变绿**不得**单独作为「没有新的静默收窄」的证据：必须坚持 §22.3b 规则 2 的三腿。

**R4（medium，脚本陈旧；已独立裁决）门② 的两个实现期证据脚本在新 HEAD 上假红。**
`mcp034` 5 条 + `mcp035` 1 条，**全部**是 `s0_head_*` 家族：它们读 `git show HEAD:…tools_list.renamed.json`
并断言**旧形状**（`animation` 成员不存在、`material_slot` 是 string）。在 `HEAD=c7bb936e00` 上契约**已经**是
override 之后的新形状，所以断言反转。我用只读 `git show` 独立复测：
`HEAD:` 契约与工作树契约**逐字节相同**（171 条），且
`editor_add_state_machine_state.animation="string"`、`editor_set_blend_tree_node.animation="string"`、
`editor_add_state_machine_transition.{xfade_time:"number", priority:"integer", advance_condition:"string"}`、
`editor_set_material_3d.material_slot="integer"` **全部存在**。
⇒ **不是实现回归**；历史脚本的「before 侧」锚点随 HEAD 前进而失效。建议：给这类 before/after 比较脚本
钉一个**显式提交锚点**（而不是 `HEAD`），或在使用前重跑并 append-only 勘误。

**R5（info）测试用端口**：除 9888/9889 外，我另开了 **9890**（无导航变体）并在收尾释放；
全程未触碰 9877（PID 36392 前后一致）。

---

## 10. next_step_recommendation

1. **可以按 171/171 收口**：① 名字并集、逐字、scope 双向、跨端点 `-32601`、组清单机器校验全部独立通过；
   ② 契约无手改（重生成逐字节）；③ 7 个 fix-first 与 2 个 unregister 的现状有自建证据；
   ⑥ 工程门 ③④ 全绿、⑤ 两次清单一致；⑦ 端口与无孤儿干净。**不需要为收口改实现**。
2. **必须做的三件小事（不阻塞收口，但应排进下一批）**：
   - 修 D1：`check_tool_groups.py` 的 usage/分派对 `--batch B1` 的说法不一致；
   - 修 D2：`project_edit_resource` 的未知键与夹取值按 §20.6 进 `ignored`（或在报告里显式登记为「已声明的偏离」）；
   - 处理 R4：给 `mcp034`/`mcp035` 等历史脚本的 before 锚点钉显式提交，避免每次 HEAD 前进都假红。
3. **本报告未证明、不得据此宣称的事项**（引用时必须带本报告锚点 `c7bb936e00`）：
   双精度构建下的 `FLOAT32` 槽行为、Android **成功**分支、§23.4 完整 19×2、B5 其余 29 个工具的不存在目标、
   `editor_get_test_report` 的编辑器内存累加器成功路径。
4. **M5 的另一半（hof-rs 切端点 + 真实 T=1 冒烟）**不在本验收范围；本报告的 pass **只**覆盖引擎侧
   B5/171 收口，不构成对 harness 侧结论的任何背书。

---

### 附：本报告的原始证据落点

| 内容 | 路径 |
|---|---|
| 自建断言结果（8 个 JSON） | `%TEMP%\audit-b5\result_{parity,contract,fixfirst,early,ergonomics,android,unregister,gate6_adversarial}.json` |
| 原始响应 + sha256 清单 | `%TEMP%\audit-b5\evidence\`（`manifest.json`、`*.req.json`、`*.res.json`） |
| `tools/list` 原始落盘 | `%TEMP%\audit-b5\toolslist_editor.json` / `toolslist_game.json`（亦见 `evidence/`） |
| 门①/②/③/④/⑤ 输出 | `%TEMP%\audit-b5\gates\`（`gate1*.txt`、`gate2*.txt`、`gate3.txt`、`gate4.txt`、`gate5_run{1,2}.txt`） |
| 门⑥ 三段 + 对抗 | `%TEMP%\audit-b5\gate6\`（`gate6_{baseline,coverage,probes,json}.txt`）+ `result_gate6_adversarial.json` |
| 组清单校验 | `%TEMP%\audit-b5\groups\`（`completeness_true.txt`、`batch_*_true.txt`、`exitcodes.txt`；`batch_B1.txt` 为最初误用 `%ERRORLEVEL%` 的一次性输出，已被 `exitcodes.txt` 取代） |
| 重建日志 | `%TEMP%\audit-b5\build.log` |
| 探针 stdout | `%TEMP%\audit-b5\{probe_c,probe_d,probe_early,probe_g,parity,unregister}.out` |
