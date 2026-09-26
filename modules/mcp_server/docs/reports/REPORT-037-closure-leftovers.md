# REPORT-037 — Godot 侧收口：B5 验收遗留 3 项 + 2 条 low 风险

> 任务书：`docs/tasks/TASK-037-closure-leftovers.md`；手册：`docs/tasks/PLAYBOOK-group-port.md`。
> 分支 `feature/mcp-server-module`，工作树基线 **`8eb7750f67`**（`docs(mcp_server): TASK-037 ... and TASK-038`）。
> 本批**不新增工具、不改契约**：`docs/tools_list.renamed.json` 工作树与 `HEAD:` **逐字节相同**
> （两边 sha256 均为 `c844ec8af9ef00d2e6ec7008c9806b3e2b16757e78794d3ccca0704edf844256`，
> `git diff HEAD` 对该文件及全部 `tool-groups*.json`、`tool-rename-map.json`、`DESIGN-DETAIL.md` **无输出**）。
> 改动只落在 `modules/mcp_server/**`（13 改 + 2 新，见 §7）。

## 0. status / commits

- **status：`done`（Godot 侧遗留为零，见 §10）**。
- **commits**：
  - `a8210611cf` — `fix(mcp_server): TASK-037 closure - unknown property and engine clamp are never silent`
    （17 files changed，1718 insertions(+)，135 deletions(-)；本报告与该提交的完整信息一致）。
  - **提交后按门纪律重绑构建**：`build_local.cmd -Force` 重建，`--version` 自报 `4.8.dev.custom_build.a8210611c`
    == `git rev-parse --short HEAD` `a8210611cf`（实现批开工时绑定的是改前的 `8eb7750f67`；
    提交本身会移动 HEAD，所以「提交后必须重建 + 复跑门」是本批执行的最后一件事）。
  - 提交后复跑（**绑定 `a8210611cf` 的重建二进制**上）：门①（`project_write_resource_scene` 3/3）、
    门②（探针 **40/40**）、门③（**262/262**、15676 断言）、门④（**1688/1688**、439958 断言）、
    门⑤（`accept_m1` ×2，22/22，PASS 清单 diff = 0）、门⑥（`scanned == pinned == 71`；覆盖探针 **101/101**）、
    以及 §9 的 6 条回归脚本（`mcp036` 59/59、`mcp035` 67/67、`mcp034` 114/114、`mcp033` 75/75、
    `mcp032` 39 checks 0 failed、`mcp030` 22 checks 0 failed）——全部 exit 0。
  - 本报告自身的**文档锚点修订**（把 `eea7b8d617` 改为 amend 之后的 `a8210611cf`，并补 §12）
    作为一条**仅文档**的 follow-up 提交落地（`git log --oneline -1`：以
    `docs(mcp_server): TASK-037 report anchors the final commit sha` 开头的那一条）。
    **该提交自身的 sha 故意不写进本报告**——写进去就必然使报告再变、提交再变、sha 再变，
    形成无法收敛的自引用（§12 第 7 条记录了这次实测）。
    `git diff --stat <实现提交> <文档提交>` 只含本报告一个文件，
    `git diff --stat` 对 `modules/mcp_server/tools`、`modules/mcp_server/tests`、
    `docs/tools_list.renamed.json` **均为空**，即文档提交不含任何被测内容。
    因此**承载全部代码的事实源是 `a8210611cf`**，运行中二进制绑定它
    （`--version` = `4.8.dev.custom_build.a8210611c`，如实反映「二进制由哪一份代码构建」）；
    文档提交之后的 HEAD 与它在代码上**逐字节相同**。绑定时序的实测见 §12。

## 1. 门（全部真实输出与退出码）

第 0 步（**从 cmd 启动、串行、不抑制输出**）：

```
# 实现批开工时（工作树 == 8eb7750f67）
modules\mcp_server\scripts\build_local.cmd -Force
build_local: exit code = 0
git rev-parse --short HEAD            -> 8eb7750f67
bin\godot.windows.editor.x86_64.exe --version -> 4.8.dev.custom_build.8eb7750f6

# 提交 a8210611cf 之后重绑（提交会移动 HEAD，必须再重建）
modules\mcp_server\scripts\build_local.cmd -Force
build_local: exit code = 0
git rev-parse --short HEAD            -> a8210611cf
bin\godot.windows.editor.x86_64.exe --version -> 4.8.dev.custom_build.a8210611c
```

两处绑定都成立（`--version` 自报前缀 == 当时的 `git rev-parse --short HEAD`）。本批共重建 8 次；
**下表所有门、以及 §3 的活证据与 §9 的回归，都是在「绑定 `a8210611cf`」的那次重建之后复跑的**
（`probe037` 40/40、门① 3/3、门③ 262/262、门④ 1688/1688、门⑤ 22/22 ×2、门⑥ 71/71 + 101/101、
回归 6/6 exit 0）。

| 门 | 命令 | 结果 | 退出码 |
|---|---|---|---|
| ① 契约子集逐字 | `check_contract_subset.ps1 -Group project_write_resource_scene`（抽 3 组之一） | `editor_9888_contract_subset` PASS、`game_9889_contract_subset` PASS、`guard_user_port_9877` PASS，3/3；`project_edit_resource`/`project_create_resource` `name=True description=True inputSchema=True` | 0 |
| ① 契约子集逐字 | `-Group editor_write_scene_editor` | 3/3 | 0 |
| ① 契约子集逐字 | `-Group running_game_read_scene` | 3/3 | 0 |
| ② 三类证据 | 本批新脚本 `scripts/probe037_d2_d1_r1r2.ps1`（见 §2/§3） | **40/40**（修复后末次运行） | 0 |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | `261 → 262` 用例、`15655 → 15676` 断言，**262/262 passed / 15676/15676 passed / 0 failed** | 0 |
| ④ 全引擎回归 | `--headless --test` | **1688/1688 passed、439958/439958 passed、0 failed**（基线 1685 → 1688，只增不减） | 0 |
| ⑤ 每批收口 | `accept_m1.ps1` **连跑两次** | 两次均 22/22，**PASS 清单逐项且顺序一致**（`Compare-Object` 空） | 0 / 0 |
| ⑥ 收窄点（三段式） | `check_narrowing_points.py` | `scanned 71 == pinned 71`，0 误报，PASS | 0 |
| ⑥ | `check_narrowing_points.py --coverage` | 17 种已声明拼写 | 0 |
| ⑥ | `mcp031_gate6_coverage_probes.ps1` | **101/101**（含 `B1_baseline_scanned_71`、`B1b_restored_scanned_71`） | 0 |

> **门⑥ 计数变化（必须显式声明，§22.3b 规则 2）**：本批在
> `tools/running_game_node_write.cpp` 的写后回读比较里新增 **2 个收窄点**（`G24-NW-SET-WIDTH`），
> 因此 `scanned/pinned` **69 → 71**，`mcp031_gate6_coverage_probes.ps1` 里两处硬编码的 `69` 同步改为 `71`
> （**不是放宽断言**：B1 的判据仍是 `scanned == pinned` 且「无未标注/未登记/陈旧条目」，探针总数 101 不变）。
> 三腿齐备：机器检查（71/71）+ 代码审查（下方两条 pin 的理由）+ 行为证据（§3 的 `hframes` 活证据）。

### 1.1 门⑥ 新增点的「点 × 闸门 × 证据」三段式

| 新增点 | 位置 | 经过的闸门 | 证据 |
|---|---|---|---|
| `request_image = Variant((double)(real_t)(double)converted)` | `running_game_node_write.cpp:1075` | 请求侧经 `prepare_node_property_value` → `coerce_to_property_type(..., ValueSlot::FROM_TARGET_TYPE)`（`FLOAT` 目标即 `REAL_T` 槽）**先判**；该 `(real_t)` 只是比较自身的宽度 | 门⑥ `[safe] G24-NW-SET-WIDTH` + 本报告 §2 D2d 活证据 + doctest `TASK-037 D2: the node property writers name an engine refusal` |
| `matches = (real_t)new_value == (real_t)converted` | `running_game_node_write.cpp:1077` | 同上；用 double 比较会把每次单精度写入误报为 `ignored`（`(double)(float)0.1 != 0.1`），与资源写者 `G24-RESOURCE-SET-WIDTH` 同因同解 | 同上 |

## 2. D2（最重要）：未知属性名与引擎夹取值不再「成功形状」

### 2.1 前后对照（9888 活证据，`curl.exe -s -o <file>` + sha256）

**(a) 完全未知的属性名**（`project_edit_resource`，`path=res://resources/curve.tres`，`{"no_such_property":1}`）

| | 响应体（逐字） | sha256 |
|---|---|---|
| 修前 | `{"id":1,"jsonrpc":"2.0","result":{"content":[{"text":"{\"changed\":{},\"message\":\"No properties were changed\",\"path\":\"res://resources/curve.tres\"}","type":"text"}]}}` | `764928368f2aee4114326b5cdd9d85d4cae7398bad2c3db605e69b5c3416b1f2` |
| 修后 | `{"error":{"code":-32001,"data":{"suggestion":"'no_such_property' is not a property of Curve; read the properties this resource really has with project_read_resource (its 'properties' object is exactly what this tool takes back)"},"message":"Property 'no_such_property' on Curve not found"},"id":1,"jsonrpc":"2.0"}` | `e33974cc6b766d343cb2a05b2ee04f9285cc34b6e2f243a6f874608dc755f5fe` |

→ 「参数存在但没动」与「参数根本不存在」**已在同一响应里可判**：前者是空 bag 的
`{"changed":{},"message":"No properties were changed"}`，后者是 `-32001` 且 `data.suggestion` **点名**该属性。

**(b) 引擎夹取值**（`project_edit_resource`，`{"min_value":5.0}`，`Curve.max_value=1.0`）

| | 响应体（逐字） | sha256 |
|---|---|---|
| 修前 | `{"changed":{"min_value":{"new":0.990000009536743,"old":0.0}},"path":"res://resources/curve.tres","type":"Curve"}` | `9750f4e7373c32a011b0a0d9be1dc0a47c0568f9f4bd1819eb1417df7bbfe781` |
| 修后 | `{"changed":{"min_value":{"new":0.990000009536743,"old":0.0}},"ignored":{"min_value":{"reason":"the engine's own property setter stored a different value for this property (it clamps or refuses input outside its own range), so it is not reported as set","requested":5.0,"stored":0.990000009536743}},"ignored_count":1,"path":"res://resources/curve.tres","properties_set":[],"type":"Curve"}` | `bc9c7057c86ffd4846df9aee0a606f35ae3af2de380c770f46b58d4ed587fba8` |

引擎依据：`Curve::set_min_value` = `_min_value = MIN(p_min, _max_value - MIN_Y_RANGE)`
（`scene/resources/curve.cpp:349-357`，`MIN_Y_RANGE 0.01` 定义于 `:318`）→ `5.0` 落成 `0.99`。
修后 `properties_set` 为空、`ignored.min_value` 带 `requested/stored/reason`、`ignored_count:1`
—— 正是 `DESIGN-DETAIL` §20.6 要求的形状。

### 2.2 实现形态（同口径的唯一一处定义）

`project_create_resource` 与 `project_edit_resource` 原先各有一份**几乎相同**的 bag 循环，差异恰好是缺陷本身
（前者成功形状跳未知键、后者连夹取值也不进 `ignored`）。本批把校验/写入/回读合并为
`project_write_resource_scene.cpp` 的 `_write_resource_properties`（前向声明 + 单一定义），规则三档：

1. 不是可设置的标识符 → **`-32602`**（参数名本身非法，`Object::set()` 只吃非空标识符）；
2. 形态合法但对象没有 → **`-32001` + `data.suggestion` 点名**（TASK-014 D-1 形状）；**整批拒绝、一个也不写**，
   因此「部分应用」不可能被读成「全部应用」；
3. 其余才写、然后**回读**：回读 ≠ 请求 → 进 `ignored{requested,stored,reason}`；
   回读 == 请求 → 进 `properties_set`。

`project_edit_resource` 另加 `properties_set` / `ignored` / `ignored_count`；`project_create_resource` 加
`ignored_count`（它本就有 `ignored`）。**空 bag 仍是原「No properties were changed」成功形状**——那是诚实的
「你什么都没给」，与「你给的名字不存在」是两件事（这正是修前无法区分的一对）。

### 2.3 同类自查表（任务书 §1.3，逐条实测）

| 工具 | 未知属性名 | 引擎夹取/拒绝 | 判定与处置 |
|---|---|---|---|
| `project_edit_resource` | **缺陷**：`{"changed":{},"message":"No properties were changed"}`（成功形状）+ exit code 0 | **缺陷**：夹取值列进 `changed`、无 `ignored` | **已修**（本批，见 §2.1/§2.2） |
| `project_create_resource` | **缺陷**：`{"changed":{},"ignored":{},"path":...,"properties_set":[],"type":"Curve"}`（成功形状；实测 sha256 `1129f6e6…`） | 已合规：夹取值进 `ignored{requested,stored,reason}`（实测 sha256 `5060f61c…`，TASK-022 D-5 已修） | **已修未知名**；夹取口径为唯一实现，顺手补 `ignored_count` |
| `editor_set_node_property` | **已合规**：`-32001` + suggestion（`Property 'no_such_property' on node 'Sprite' not found`，TASK-014 D-1 已修） | **缺陷（分类缺失）**：`hframes=0` 被 `Sprite2D::set_hframes` 拒绝，响应只有 `{"new_value":<旧值>}`，调用方须自行比较才能发现；无 `ignored` | **已修**：共享 `write_node_property` 增加 `ignored{<prop>:{requested,stored,reason}}`（§2.4） |
| `editor_set_node_property_batch` | **已合规**：`-32001`，且在任何写入之前（TASK-018 预检） | **缺陷（分类缺失）**：回 `{"updated":1,"status":"ok"}`，夹/拒绝完全不可见 | **已修**：回读按节点路径聚合 `ignored` + `ignored_count`（§2.4） |
| `running_game_set_node_property` | **已合规**：`-32001` + suggestion | 同上（共享 `write_node_property`） | **已修**：随共享函数同口径获得 `ignored` |
| `editor_add_node` / `editor_add_nodes_batch`（`apply_node_properties`） | **已合规**：`-32001`（TASK-014 形状，半建节点被销毁） | 走同一 `write_node_property`，批量失败即整体回滚 | 随共享函数获得逐属性 `ignored`（批量事务语义不变） |
| `project_set_node_property_across_scenes` | 走同一 `set_node_property_across_scenes` → `write_node_property` | 同 | 随共享函数同口径 |
| `particle_shared::write_node_member` 家族（`editor_create_particles_preset` 等） | 不存在该形态（参数是固定 spec 列表） | **已合规**：`ignored[{property,requested,stored,reason}]` + `ignored_count` + `node_properties_ignored` | 无需改（TASK-033 已落 §20.6） |
| `theme_shared::build_theme_write_result`（`project_set_theme_color/constant/font_size/stylebox`） | `Theme::is_valid_item_name` 先行 → `-32602` | **已合规**：`ignored{<item>:{requested,stored,reason}}` + `properties_set` | 无需改；`project_set_theme_font_size` 另见 §5 R2 |
| `project_set_setting` | key 形态由 `ProjectSettings` 判定 | 实测 `display/window/size/viewport_width = -5` **被引擎原样保留**（回 `value:-5`，无 `ignored` → 正确：这里没有夹取） | 无需改（记录实测，见 §3 的 `A08`） |

**共同点（本批的统一口径）**：一个写工具的成功响应里，**凡是调用方给的值没有被原样存下**，就必须能从响应本身
判断出来（错误码，或 `ignored{requested,stored,reason}` 点名）；**仅靠「回显了真实存储值」不再被视为足够**，
因为那要求调用方自己记住并比较请求。

### 2.4 节点写族的 `ignored`（活证据）

实测（9888，`editor_set_node_property` `path=Sprite, property=hframes, value=0`）：

| | 响应体（逐字） |
|---|---|
| 修前 | `{"id":1,"jsonrpc":"2.0","result":{"content":[{"text":"{\"new_value\":1,\"node_path\":\"Sprite\",\"old_value\":1,\"property\":\"hframes\"}","type":"text"}]}}` |
| 修后 | `{"new_value":4,"node_path":"Sprite","old_value":4,"property":"hframes","ignored":{"hframes":{"reason":"the engine's own property setter stored a different value for this property (it clamps or refuses input outside its own range), so it is not stored as asked","requested":0,"stored":4}}}` |

引擎依据（实测 + 引擎源码）：`Sprite2D::set_hframes` 对 `< 1` **拒绝并保持原值**，引擎日志
`ERROR: Amount of hframes cannot be smaller than 1.`（本批 doctest 红→绿过程里实测到两次）。
因此这是「拒绝」而非「夹取」，`stored` 是引擎**真实持有**的旧值（活证据里为 `1`，doctest 里为 `4`，
两者都等于写入前的值），这正是 `ignored.stored` 的语义。

批次写者实测（`editor_set_node_property_batch` `node_type=Sprite2D, property=hframes, value=0`）：
修前 `{"updated":1,"status":"ok"}`，修后带
`"ignored":{"Sprite":{…requested:0,stored:9…}},"ignored_count":1`。

**判断口径的取舍（必须显式声明）**：`ignored` 的比较对象是 **coerce 之后**的值，不是原始 JSON ——
`DESIGN-DETAIL` §20.4 的**已声明确定性转换**（`1.9 → 1` 进 int 槽、`"#ff0000"` → Color、对象按分量拆解）
**不算夹取**，不得报成「引擎改了我的值」。doctest 第 (4) 段把这条钉住。
`a:b` 子属性路径（`set_indexed` 回写整个复合体）不参与该比较，理由写在源码注释里：
按分量比较会把姊妹分量的正常归一化误报为夹取；该情形由既有的 `parent_old_value`/`parent_new_value` 呈现。

## 3. 门② 三类证据 + 联系人链（`scripts/probe037_d2_d1_r1r2.ps1`，40/40）

脚本自带 scratch 工程、`--import` 走共享助手 `mcp_import_guard.ps1`（校验退出码 + 有界重试 + 诊断），
响应体一律 `curl.exe -s -o <file>` 落盘并算 sha256，请求体用 `ConvertTo-Json` + `--data-binary @file`，
**逐条断言**（`A01`…`A13`）。诱饵/失败类证据的真实码：

| id | 工具 | 类别 | 实测 |
|---|---|---|---|
| `A01_edit_unknown` | `project_edit_resource` | 未知属性名 | `-32001` + 点名 `no_such_property` |
| `A02_edit_clamped` | `project_edit_resource` | 引擎夹取 | `0` + `ignored.min_value{5.0 → 0.990000009536743}` |
| `A03_create_unknown` | `project_create_resource` | 未知属性名 | `-32001` + 点名；**且未落盘任何文件**（`D2c_create_unknown_left_no_file`） |
| `A04_create_clamped` | `project_create_resource` | 引擎夹取 | `0` + `ignored_count:1` |
| `A05_node_unknown` | `editor_set_node_property` | 未知属性名 | `-32001`（缺陷类，判据=**不可**构造成功形状） |
| `A06_node_batch_unknown` | `editor_set_node_property_batch` | 未知属性名 | `-32001`（同上，整批拒绝） |
| `A07/A07b/A07c` | 节点写族 | 引擎拒绝 | `new_value` 与 `editor_get_node_properties` 读回**逐字一致**；`ignored.hframes` 点名 |
| `A08_setting_clamped` | `project_set_setting` | 无夹取 | `value:-5` 原样保留（记录，不误报 `ignored`） |
| `A09` | `editor_set_shader_material` | R1 成功路径 | `material_slot:"material_override"`，`material_slots[0]` 同值 |
| `A10` | `editor_set_shader_material` | R1 反例 | 显式 `material_slot:"material"` 仍 `-32602` 并列出真实槽位 |
| `A12` | `project_set_theme_font_size` | R2 反例 | `size=0` → `-32602`，文件无该条目 |
| `A12b`/`A13` | 同一对工具 | R2 正例 | `size=21` → `font_size_readable:true`，读者 `font_sizes.Button.good_size=21` |

**联系人链（跨工具、可观察状态变化）**：`A01`（未知名被拒，**先算 sha256**）→ `A02`（夹取值写入 + `ignored`）
→ `A09`（`editor_set_shader_material` 省略槽位 → 拿到 `material_slot:"material_override"`）
→ `A07b`（`editor_get_node_properties` 读回，与写入响应逐字互证）。
**读侧唯一性验证**：`ignored.stored` 总是与「另一个读工具读到的引擎真值」相等
（`D2d_the_answered_value_is_the_engine_value`、`D2d_node_ignored_stored_is_the_engines_real_value`）。

**不可构造类的声明**：`project_edit_resource` 的「底层失败」三类已由既有 doctest
（不存在 → `-32001`；不可加载 → `-32001`；`properties` 非对象 → `-32602`）覆盖，本活证据脚本**不再重复**，
因为 9888 上的 scratch 工程无法在半途制造「文件存在但不可加载」而不污染后续步骤；
该类的真实证据在门③ 的 `[MCPServer] the write tools never corrupt an existing file when the call fails`
（本批重跑通过）。**没有伪造任何响应**。

## 4. D1：`check_tool_groups.py --batch B1`

**选择**：让 `--batch B1` **等价于无参数路径**（任务书二选一中的第二项）。理由：无参数路径就是 B1 不变式的
冻结实现 `main()`，把它作为 B1 的显式别名，**断言强度为零变化**（同一条代码路径、同一个退出码），
而 usage 措辞随之变真；改措辞则会让「B1 只能靠隐式无参数调用」这一反直觉事实保留下来。

实测（`python probe037_d1.py`，逐条 `subprocess` 取真实 `returncode` 与 stdout sha256）：

| 调用 | exit | stdout sha256(前 24) | 末行 |
|---|---|---|---|
| 无参数 | **0** | `ca198e9842b7863842350f16` | `TOOL-GROUPS CHECK PASS` |
| `--batch B1` | **0** | `ca198e9842b7863842350f16` | `TOOL-GROUPS CHECK PASS` |
| `--batch B2` | 0 | `9a73aba78db73ec4c2a746fa` | `TOOL-GROUPS-B2 CHECK PASS` |
| `--batch B3` | 0 | `758893898b72d85bd43ec988` | `TOOL-GROUPS-B3 CHECK PASS` |
| `--batch B4` | 0 | `df9f2b90f9786f1b19dcdaf3` | `TOOL-GROUPS-B4 CHECK PASS` |
| `--batch B5` | 0 | `df123d5abdb540fe2becbec6` | `TOOL-GROUPS-B5 CHECK PASS` |
| `--check-completeness` | 0 | `3e33af4ddb237591214597bc` | `TOOL-GROUPS-COMPLETENESS CHECK PASS` |
| `--batch B9`（未知） | **1** | `e3b0c44298fc1c149afbf4c8`（空 stdout） | `usage: … (unknown batch: B9)`（stderr） |

**`--batch B1` 与无参数 stdout 逐字节相同**（`FC /b` 报 `no differences encountered`；Python 侧 sha256 相等、
退出码相等）。未知批次仍 `exit 1`（判据未被放宽）。usage 字符串统一为
`[--batch B1|B2|B3|B4|B5]`（原先无参数分支残留的 `[--batch B2]` 也已改正），docstring 与 TASK-015 注释同步更新。

## 5. R4 与两条 low 风险

### 5.1 R4：历史证据脚本的 `before` 锚点钉成显式提交

`mcp034`/`mcp035` 的 6 条 `s0_head_*`（`mcp034` 5 条 + `mcp035` 1 条）原先读 `git show HEAD:…renamed.json`
并断言**旧形状**。契约改动（`d744a100bc` 的四个 B5 batch 2 SCHEMA_OVERRIDES）与 `material_slot` 的
`string → integer` 都是**这两个脚本各自提交的祖先**，所以脚本被跟踪时它的「before」已经消失
→ 每个后续 HEAD 上都假红（B5 验收实测 109/114 与 66/67）。

钉锚点（两个脚本都加了 `MCP034_BASE_REF` / `MCP035_BASE_REF` 环境变量覆盖）：

```
$BaseRef = if ($env:MCP034_BASE_REF) { $env:MCP034_BASE_REF } else { 'fc724ce49a' }
$headText = (& git -C $RepoRoot show ($BaseRef + ':modules/mcp_server/docs/tools_list.renamed.json')) -join "`n"
```

选 `fc724ce49a`（`docs(mcp_server): TASK-034 brief (B5 batch 2 + four schema overrides), the 22.3b/23.4 updates and REPORT-033`）
的理由与验证：

1. 它是 `d744a100bc`（四个成员进场）的**父提交**，即「旧形状」的最后一个提交；
2. 它同时满足 `mcp035` 的 before（`editor_set_material_3d.material_slot.type == "string"`，在该提交实测为 `string`）；
3. **6 条断言逐条在 `fc724ce49a` 上实测 PASS**（`animation` 缺失 ×2、`xfade_time`/`priority`/`advance_condition`
   缺失 ×3、`material_slot` 为 string ×1；`$headText.Length > 1000` 亦成立），且
   `git merge-base --is-ancestor fc724ce49a HEAD` 为真（可达、可复现）；
4. **断言一条未删、一条未改方向**（判据不变，只换读的版本）；证据文本里的「HEAD's contract」改为
   「the pinned base contract (`fc724ce49a`)」，**写明这是记录于该提交的快照**；检查 id 保留（下游审计脚本按 id 引用）。

**重跑实测**：`mcp034` **114/114 exit 0**、`mcp035` **67/67 exit 0**（修前分别为 109/114、66/67）。
即：**不是实现回归的独立裁决被本批的实测证实**。

### 5.2 `scripts/**` 里对 `HEAD` 的引用普查（逐条判定）

**普查方式**：`grep -n "HEAD"` 覆盖 `scripts/**`（含 `*.py` 与 `*.ps1`），并对每条命中读上下文判定用途。
`docs/scripts/*.py` 中的 `HEAD` 全是 `HEADERS`/`HEADER` 字面量（`selfcheck.py`、`gen_table.py`），非 git 引用。

| 脚本 | 行 | 引用形态 | 用途 | 判定 |
|---|---|---|---|---|
| `mcp034_…evidence.ps1` | 397 | `git show <BaseRef>:` | 契约 before 快照 | **必须钉锚点** → `fc724ce49a`（本批） |
| `mcp035_…evidence.ps1` | 382 | 同上 | 契约 before 快照 | **必须钉锚点** → `fc724ce49a`（本批） |
| `mcp018_b3_closure_evidence.ps1` | 429 | `git show <BaseRef>:`（`$BaseRef` 默认 `ddb585d888`，可用 `MCP018_BASE_REF` 覆盖） | `accept_m1.ps1` 旧字面量 + 三个旧 manifest 的 before 快照 | **已钉锚点**（TASK-018 起，本批复核未动） |
| `mcp025_gate6_index_experiments.ps1` | 29/45-51 | 参数 `-PreTask025Commit`（默认 `0b120996ff`） | 「TASK-025 之前的 guardrail 脚本」对照 | **已钉锚点**（注释已写明「never against HEAD，因为 HEAD 上是替换后的脚本」） |
| `mcp016_hoist_equivalence.ps1` | 21/47/48/170/175/448 | `rev-parse --short HEAD` | ①事前记录 `$StartHead`；②按门纪律校验 `--version` 前缀 == 当前 HEAD；③结束时恢复分支/HEAD | **必须随 HEAD**（这正是子代理开跑门前「二进制绑定 HEAD」的检查本身；换成固定提交会把这条纪律整条作废） |
| `mcp022_unified_narrowing_gate_evidence.ps1` | 719 | `rev-parse --short HEAD` | `G0_version_matches_head` 门 | **必须随 HEAD**（同上） |
| `mcp023_narrowing_guardrail_evidence.ps1` | 1035 | `rev-parse --short HEAD` | 同上 | **必须随 HEAD** |
| `mcp018` | 344 | `rev-parse --short HEAD` | 运行时记录 | **必须随 HEAD**（记录结论锚点） |
| `mcp019` / `mcp020` / `mcp021` / `mcp024b` / `mcp025_e3` / `mcp025_gate6` / `mcp026` / `mcp028_*` / `mcp029` / `mcp030` / `mcp031` / `mcp032` | 各 1 处 | `rev-parse --short HEAD` | 记进 summary/日志 | **必须随 HEAD**（D86：结论必须能标到运行时的提交；若改成固定提交，记录就变成**错的**） |

**结论**：`scripts/**` 里**只有** `git show <ref>:` 形态的引用承担「历史对照」职责，共 4 个脚本，
现已**全部**钉成显式提交（`mcp018`/`mcp025` 原本已钉，本批补齐 `mcp034`/`mcp035`）；
其余全部是「记录本次运行锚点」或「按门纪律校验二进制 == 当前 HEAD」，**必须继续随 HEAD**，
不做任何改动。`HEAD` 在 `cmd`/PowerShell 里的传递已加引号/括号（`git show ($BaseRef + ':' + path)`），
避免 `^` 与路径拼接的转义问题。

### 5.3 R1：`editor_set_shader_material` 的默认 `material_slot`

**契约冻结**：`inputSchema.properties.material_slot = {"default":"material","type":"string"}`
（改默认值需要 `SCHEMA_OVERRIDES`，本批明令不允许）。**选择：让省略时按节点类型解析默认槽**（任务书选项一）。

- `resolve_material_slot` 增加 `p_argument_present`；**显式**给出 `"material"` 而节点没有该属性时
  仍是 `-32602` 并列出真实槽位（判据未放宽，`A10` 实测）；
- **省略**时：`material` 属性存在就用它（`CanvasItem` 行为不变），否则取该节点 `get_property_list()`
  顺序里的**第一个**材质槽，并在响应 `material_slot` 里点名实际写入的槽。
- 实测（9888，`MeshInstance3D` 省略 `material_slot`）：
  `code=0`、`applied=true`、`material_slot="material_override"`、
  `material_slots=["material_override","material_overlay","surface_material_override/0"]`，
  且探针断言 `material_slot == material_slots[0]`（不是硬编码字符串，随引擎属性序）。
- 为什么优先取「第一个槽」而不是「surface 0」：`material_override` 是 `GeometryInstance3D` 的整节点覆盖槽，
  对省略参数的调用者语义最接近 `CanvasItem.material`；`surface_material_override/<n>` 需要调用方先知道表面数
  （数字索引写法与显式拼写仍然完全可用）。
- **不做**：改契约默认值（需 override）；把错误消息改成「默认值只适用于 CanvasItem」而不修行为
  （那仍然让「按 schema 填默认值」的客户端在 3D 上直接失败，只是失败得更好看）。

### 5.4 R2：`project_set_theme_font_size(size<=0)` 与读者不一致

**实测根因（在修前二进制上量到，构成选择依据）**：写入器对 `size=0` 回
`ignored{requested:0, stored:null, …}` + `font_size_readable:false`（诚实）；但引擎的序列化器把该条目
**落盘成回退字号**——scratch 工程 `ui/theme.tres` 实际字节为
`Button/font_sizes/zero_size = 16`（sha256 `aff42d99e42e8950e4c213c87cef3f9ea7c1090bbe769ae30387d1fa4590c23a`），
而 `project_get_theme_info` 随后把它列进 `font_sizes.Button.zero_size = 16`，
`font_sizes_stored_not_readable` **为空**。即：同一个条目，写者说「读不回来」，读者说「被设置成 16」。

**选择：写入器拒绝 `<= 0`（`-32602`）**，理由：

1. 调用方要的尺寸**根本无法被存下**（`Theme::_get` 对 `<= 0` 答回退，`scene/resources/theme.cpp:661-671`），
   所以诚实的答案就是「参数非法 + 说明为什么」，而不是写一个必然读不回来的值；
2. 「报成功」与「引擎偷偷存了 16」不能同时为真；拒绝后条目**根本不存在**，
   两个工具的说法自动一致（无需让读者去猜某个 `16` 是用户写的还是回退）；
3. 读者侧方案（给回退条目打标）需要读者知道「哪一个 16 是回退」，而引擎没有提供这个信息——
   会把猜测固化进契约形状；
4. 这也是 `KNOWN` 的取舍：`size<=0` 的旧行为**本来就没有可用语义**（读回来永远不是请求值），
   拒绝不减少任何可用能力；`size > 0` 的路径完全不变（`A12b`/`A13` 实测）。

**一致性的实测证据**：修后 `size=0` → `-32602`，主题文件里**没有** `zero_size` 条目
（`ui/theme.tres` 只含 `Button/font_sizes/good_size = 21`，sha256 `b2d779a4d0f4039c11e9e13ef3835fe58eefbaff704a47666c5ca68af8c2cded`），
读者 `font_sizes_stored_not_readable == []` 且查不到 `zero_size`。

## 6. 受影响证据脚本清单与处置（任务书 §1.4）

**判据：不得为让脚本变绿而放宽断言；确需改动时按「缺陷已修 → 证据脚本必须随之收紧」处理。**

| 文件 | 改动 | 归因 |
|---|---|---|
| `modules/mcp_server/tests/test_mcp_server.h` | `project_edit_resource rewrites an existing resource and **skips unknown properties**` → 重命名为 `… reports every written property`，未知键从「被跳过」改为「`-32001` 点名」；新增用例 `TASK-037 D2: project_edit_resource names an unknown property and an engine clamp`、`… project_create_resource names an unknown property and a clamp too`、`… the node property writers name an engine refusal`；`project_edit_resource reports no change …` 改为只覆盖**空 bag** 的 `No properties were changed`（原来用未知键构造该形状）；`resolve_material_slot` 全部调用点补 `p_argument_present` + 新增 R1 的省略/显式对照断言；`theme_set_font_size(size=0)` 由「ignored 期望」改为「`-32602` 期望」并补 `size=1.5` 的 `-32602` 与正例；TASK-036 的 `font_sizes_stored_not_readable` 由「含 `zero_size`」改为「为空 + 无 `zero_size` + 有 `font_size=16`」 | 断言**变强**（原来把缺陷当规范钉住；新断言钉住修复后的可诊断性）；`git diff` 的删除行已逐行复核（§6.1） |
| `mcp034_…evidence.ps1` / `mcp035_…evidence.ps1` | 锚点钉 `fc724ce49a` + 证据文本写明「pinned base contract」 | R4；断言强度不变 |
| `check_narrowing_points.py` | 新增 `G24-NW-SET-WIDTH` 两条 pin（含理由） | 门⑥ 要求；**新增点必须登记**，不是放宽 |
| `mcp031_gate6_coverage_probes.ps1` | `69` → `71` 两处，并更新说明注释 | 同上；探针总数与判据结构不变 |
| `check_tool_groups.py` | B1 别名 + usage 统一 | D1；不变式强度不变（同 `main()`、同退出码，stdout 逐字节相同） |
| **未受影响（已实测重跑通过）** | `mcp007`、`mcp020`、`mcp021`、`mcp022`、`mcp023`、`mcp026`、`mcp027` 里对两个资源写者的调用 | 它们的 bag 全部由 `project_read_resource` 的 `properties` 对象直供，**每个键都是对象的真实属性**（`project_read_files.cpp:418-433` 只回 `PROPERTY_USAGE_STORAGE` 的真属性），所以不会踩「未知名」；`mcp020/021` 的 `-32602` 反例（`offsets=1e300`、`data=300`）在**回读之前**就被收窄闸门拒绝，与本次改动无关 |

### 6.1 被删断言的逐行复核（防止「悄悄放宽」）

`git diff HEAD -- tests/test_mcp_server.h` 中被删除的行**全部**属于下列 5 类，无一条是「因为做不到而删掉」：

1. `project_edit_resource … skips unknown properties` 的用例名与 `properties["mcp_no_such_property"] = 1;`
   / `CHECK_FALSE(changed.has("mcp_no_such_property"))` → 被 §2.1 的 `-32001` 断言取代；
2. `Only unknown properties: …` 注释块 + 该 bag 的 3 行 → 改为 **空 bag** 版本（
   `CHECK(FileAccess::get_file_as_string(target) == before)` **保留**，缩进修正为与 `CHECK` 对齐）；
3. `resolve_material_slot(..., slot, ...)` 旧签名的 6 行 → 同语义 + 新签名的 6 行（另加 R1 省略分支断言）；
4. `theme_set_font_size(size=0)` 的 `ignored` 期望 8 行 → 被 `-32602` 期望的 8 行取代（另加正例）；
5. TASK-036 的 `CHECK(((Array)info["font_sizes_stored_not_readable"]).has("zero_size"))` 1 行 →
   被 4 行取代（空 bag + 无 `zero_size` + `font_size=16`）。

因此**没有任何一条断言被削弱**：被删的每一行都对应一条**更强或等强**的新断言；`des asserted` 数从
15655 → 15676（**只增**）。

## 7. 改动清单与 sha256

| 文件 | 类别 | sha256 |
|---|---|---|
| `tools/project_write_resource_scene.cpp` | D2 主体（`_write_resource_properties` + 两个工具） | `ebe85224be9374b0974bab1f56b010a9ea1fad7e2b69e87245a8fac827126f10` |
| `tools/project_write_resource_scene.h` | 不变式 4 写入头注释 | （未单列，随 .cpp 同批） |
| `tools/running_game_node_write.cpp` | D2 同类自查：`write_node_property` 的 `ignored` | `69b1c7f976b06674f6a8a3e3a77325488fb600a2d684593fa26cfd037622164e` |
| `tools/editor_node_batch_write.cpp` | D2 同类自查：批次 `ignored`/`ignored_count` | `1064883d5515b57432a2e49b29bd7b5cfdde5bdde12a2db3c701638e0c73cfe5` |
| `tools/shader_shared.cpp` / `.h` | R1 默认槽解析 | `8cf409b0b9ae1f6298e3845eb1e2ecdeab3ce402e1168db722abd65214c78d09` |
| `tools/editor_shader_write.cpp` / `.h` | R1 传 `p_slot_present` | `ea8965c77bf265d2a19385672d86556a98fff19406d20c014667f576aa0ef024` |
| `tools/project_theme_write.cpp` | R2 拒绝 `<= 0` | `969b09e4f7cfe8b03cbdb723630aa16362b798ad200b69dfe1ea12d1bdb1e863` |
| `tests/test_mcp_server.h` | 红/绿 + 新用例 | `2e8b9d2430bc2ac7058949ec5f768765aae619174bb584e2f15bae455c38e2bd` |
| `docs/scripts/check_tool_groups.py` | D1 | `9923559b76190c6206d1476666b8be911029e6c70053e934d9334c3533bd29c2` |
| `scripts/check_narrowing_points.py` | 门⑥ 新 pin | `469b7f9977cd9520442bef8c26fa30dc0a9e9775d5d3d54bd46d9601b6884244` |
| `scripts/mcp031_gate6_coverage_probes.ps1` | 门⑥ 计数 | `518db7a9b4827fcba4b8a8d59e179663c82568fac124aa98b202c3e76d9f8fb8` |
| `scripts/mcp034_…evidence.ps1` | R4 锚点 | `c0f2a930be9937850bb8d240dae100079a23ef6b46ba17cbc9000ccc64c80a33` |
| `scripts/mcp035_…evidence.ps1` | R4 锚点 | `edef0c25cb4cd5f3afcc21648540b2029ffc15d4e87a8e55dc0ac17ac7060f50` |
| `scripts/probe037_d2_d1_r1r2.ps1`（**新增**，纯 ASCII，已校验 0 个非 ASCII 字节） | 门② 证据 | `5b642f6a9fe6ea5f0c70f7690abec0a7e4824b82ca0c5efb182c1a2c31077f32` |
| `docs/tools_list.renamed.json`（**未改**，逐字节等于 `HEAD:`） | — | `c844ec8af9ef00d2e6ec7008c9806b3e2b16757e78794d3ccca0704edf844256` |

## 8. 红/绿证据（TDD）

本批按 TDD 走：先改测试到「期望新行为」并跑出**真实红**，再改实现到绿。红阶段实测（同一二进制的
`--test-case="[MCPServer]*"` 输出片段）：

```
TEST CASE:  [MCPServer] TASK-037 D2: project_edit_resource names an unknown property and an engine clamp
  ... 多处 ERROR: CHECK(...) is NOT correct!   （未知键返回成功形状、夹取值无 ignored）
TEST CASE:  [MCPServer] TASK-035 the shader material slot is resolved and written, not hard-coded
.\modules\mcp_server\tests\test_mcp_server.h(19249): ERROR: CHECK( String(slot) == "surface_material_override/0" ) is NOT correct!
TEST CASE:  [MCPServer] TASK-036 the theme writers store what they were asked and read it back
.\modules\mcp_server\tests\test_mcp_server.h(19872): ERROR: CHECK( ((Array)info["font_sizes_stored_not_readable"]).has("zero_size") ) is NOT correct!
```

红阶段里两次被**实测**捕获的细节（写进了实现注释，避免后来者再踩）：

1. `MeshInstance3D` 的**第一个**材质槽是 `material_override`（不是 `surface_material_override/0`）
   —— R1 的断言因此改成「等于 `material_slots[0]`」而不是硬编码字符串；
2. `Sprite2D::set_hframes(0)` 是**拒绝并保持原值**（引擎打印 `ERROR: Amount of hframes cannot be smaller than 1.`），
   不是「夹到 1」—— 因此 `ignored.stored` 是**写入前的值**，被写成引擎真实持有的值。

绿阶段：

```
[doctest] test cases:   262 |   262 passed | 0 failed | 1429 skipped
[doctest] assertions: 15676 | 15676 passed | 0 failed |
[doctest] Status: SUCCESS!
```

## 9. 回归：逐条归因（不得只报「全绿」）

`scripts` 逐条重跑（串行、真实退出码），**在绑定 `a8210611cf` 的重建二进制的最终一轮里再次全部 exit 0**
（下表计数即该轮的实测值）：

| 脚本 | 本批 | B5 验收基线 | 归因 |
|---|---|---|---|
| `mcp036_b5_navigation_theme_export_android_evidence.ps1` | **59/59 exit 0** | 59/59 exit 0（`REPORT-AUDIT-B5`） | 无回归；本批未动该组实现 |
| `mcp035_b5_tilemap_shader_physics_evidence.ps1` | **67/67 exit 0** | 66/67 exit 1 | **R4 锚点修复后由红转绿**：唯一红项 `s0_head_material_slot_is_string` 现在读 `fc724ce49a`。B5 验收已独立裁决其为陈旧锚点；本批实测证实（且未动该组任何实现） |
| `mcp034_b5_audio_particle_theme_evidence.ps1` | **114/114 exit 0** | 109/114 exit 1 | 同上：5 条 `s0_head_*` 现在全部指向 `fc724ce49a`。无实现改动 |
| `mcp033_b5_animation_evidence.ps1` | **75/75 exit 0** | 75/75 exit 0 | 无回归 |
| `mcp032_d3_d4_d6_evidence.ps1` | **39 checks, 0 failed, exit 0** | 39/39 | 无回归 |
| `mcp030_live_open_scene_write_evidence.ps1` | **22 checks, 0 failed, exit 0** | 22/22 | 无回归：`project_edit_resource` 的改动未触及该链的 bag（全部是节点/场景写入） |

**本批自身改动引起的、需要归因的每一处回归风险**（都不存在「未解释的绿」）：

1. **`project_edit_resource` 未知键由成功变 `-32001`** → 受影响面已普查（§6）：所有历史脚本的 bag 都来自
   `project_read_resource.properties`（只含真属性）或字面量真属性名；6 条回归脚本实测全绿；
2. **`editor_set_node_property*` 增加 `ignored` 字段** → 属**新增**字段（不是形状替换），
   既有断言都是逐键取值，无「键集相等」断言（`grep old_value|new_value` 43 处逐条看过）；
3. **`theme_set_font_size(<=0)` 由成功变 `-32602`** → 历史脚本无 `size<=0` 调用
   （`mcp034` 用 19、`mcp036` 用正数；`mcp033` 不涉及主题写）；
4. **R1 默认槽解析变化** → 只在**省略** `material_slot` 时生效；历史脚本**全部显式**传槽
   （`mcp035` 传 `material_override`、`mcp036` 传 `material_override`），实测全绿；
5. **门⑥ 计数 69 → 71** → 已同步 `mcp031_gate6_coverage_probes.ps1`（101/101 exit 0），
   且 `check_narrowing_points.py` 本体 scanned==pinned。

## 10. Godot 侧遗留为零的声明

| 来源 | 项 | 状态 |
|---|---|---|
| B5 验收 D2 | `project_edit_resource` 未知键/夹取值 | **已修**（§2） |
| B5 验收 D2 同类自查 | `project_create_resource`、`editor_set_node_property` 家族 | **已修**（§2.2/§2.3/§2.4） |
| B5 验收 D1 | `check_tool_groups.py --batch B1` | **已修**（§4） |
| B5 验收 R4 | `mcp034`/`mcp035` 锚点 + `scripts/**` 普查 | **已修**（§5.1/§5.2） |
| B5 验收 R1 | `editor_set_shader_material` 默认槽 | **已修**（§5.3） |
| B5 验收 R2 | `project_set_theme_font_size` 与读者不一致 | **已修**（§5.4） |

**残余（非本模块可修，如实列出，不声明为「已解决」）**：

1. **`Android`/export 成功分支**：本机无 SDK/模板/设备，「有设备时真能装」仍**不可验证**
   （B5 验收 `unconfirmed` 2 项，本批未触碰，维持「已声明的不可验证能力」）；
2. **门⑥ 的保证仍是有限拼写集合**（B5 验收 R3）：本批新增点是「拼写可见」的 `(real_t)` 比较，
   已按三腿登记；运行时隐式 `double → real_t`、整数收窄、集合外拼写仍在门⑥ 之外，
   只能靠代码审查 + 行为证据；
3. **`§23.4` 读回矩阵**：`Transform2D/Transform3D`、`Basis`、`Plane`、`Projection`、`AABB` 仍无工具读回（既有欠账）；
4. **单精度之外的构建**：`ValueSlot::FLOAT32` 在 `precision=double` 下仍只有源码级 + 单元级结论；
5. **`Sprite2D.hframes` 这类「引擎拒绝并保持原值」的写法**：本批只把节点写族纳入 `ignored`。
   其它**专用 setter 路径**（视口相机 `position`/`rotation_degrees`/`fov`、环境颜色、输入事件坐标/strength）
   本批**未**逐一构造「被拒绝」实例，仍是「回显即诚实」的既有口径（不属 §20.6 的 `properties` bag 范畴，
   但若后续要统一，应作为独立任务评估）。

## 11. deviations / blockers / next_step_recommendation

**deviations（逐条显式）**

1. **门⑥ 计数与探针脚本硬编码从 69 改为 71**。这是本批新增 2 个真实收窄点的**必然结果**，
   不是放宽判据；参照 PLAYBOOK 门⑥ 的「计数随批次增长」既有先例（30→34→38→69）。
2. **`theme_set_font_size(<=0)` 从「接受 + ignored」改为「拒绝 `-32602`」。**
   任务书给了二选一；本报告 §5.4 给了选择与理由（含「引擎把 `<=0` 落盘成回退 16」的实测字节证据）。
   这**改变了该工具的失败语义**（原先 `code=0`），属任务书明确授权的选项。
3. **`project_edit_resource` 对「未知键」选择整体拒绝而非部分写入 + `ignored`。**
   任务书允许两种形态；选择拒绝的理由是「部分应用」无法被读成「完整应用」，且拒绝发生在任何写入之前
   （文件 sha256 不变，实测 `D2a`/`D2c` 均未落盘）。
4. **节点写族的 `ignored` 只覆盖「单属性」（非 `a:b` 子属性路径）与「拼写合法」的 key。**
   子属性路径的理由写在源码注释；`ignored` 的比较对象是 coerce 后的值（§2.4）。
5. **`editor_set_node_property` 的「引擎拒绝」不是「引擎夹取」**：实测结论（引擎保持原值并打 ERROR）
   与任务书的措辞（「引擎静默忽略」）在语义上更接近「拒绝」，本报告按实测命名，并把 `stored` 定义为
   「引擎事后真实持有的值」。
6. **`check_tool_groups.py` 无参数分支的 usage 文本从 `[--batch B2]` 改为 `[--batch B1|B2|B3|B4|B5]`。**
   TASK-015 注释称该行「byte for byte 冻结」，但它实际引用的是**错误**的 usage；不改它就会保留
   「usage 与实际不符」这一 D1 的同一类问题。B1 的不变式与退出码均未变（stdout 逐字节相同）。

**blockers**：无。

**next_step_recommendation**

1. 本批已提交：**实现 + 报告 = `a8210611cf`**（承载全部代码，运行中二进制绑定它），
   随后一条**仅文档**的锚点修订提交（见 §0，sha 故意不自引用）。工作树只剩既有未跟踪物
   `.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`。
   `DECISIONS.md` 的对应条目由决策者写入（本 fork 内不维护竞争性决策日志）。
2. TASK-038（opt-in MCP call trace）可在此基础上开跑；本批未触碰 trace 相关代码路径。
3. 若后续要收口 §10 残余 5，建议单独立项：把「专用 setter 路径的拒绝/夹取」也纳入可判形状，
   并同步补门⑥ 的对应拼写探针。
4. 门⑥ 的 71 是**同一批次内**的计数；下一次新增收窄点的批次需再次同步
   `mcp031_gate6_coverage_probes.ps1` 的两个硬编码值（该脚本的注释已写明这条维护义务）。

## 12. 绑定时序（本批踩到并记录的流程事实）

**「提交会移动 HEAD」与「门必须先绑定 HEAD」是两条互相追逐的纪律**，本批的执行顺序与实测如下，
供后续批次直接照用：

1. 实现与全部门在 `8eb7750f67` 上跑绿（`--version` 自报 `8eb7750f6`）；
2. 提交 → HEAD 变为 `eea7b8d617`，**二进制立刻落后 HEAD**（门若此时开跑会判 `--version != HEAD`）；
3. 重建 → `--version` = `eea7b8d61`，与 HEAD 一致；复跑门① 3/3、② 40/40、③ 262/262、④ 1688/1688、
   ⑤ 22/22 ×2、⑥ 71/71 与 101/101、回归 6/6 —— 全绿；
4. 发现报告里的提交号写成 amend 之前的 `eea7b8d617`；`git commit --amend` 把提交号改成 `a8210611cf`，
   **HEAD 再次移动**；
5. 重建 → `--version` = `a8210611c`，与 HEAD 一致；**再次复跑全部门与 6 条回归**（结果与第 3 步相同）；
6. 只改报告文字（把 `eea7b8d617` 更正为 `a8210611cf`）并作为**仅文档**提交落地 ——
   该提交不含任何 C++/头文件/契约改动，因此 `--version` 与二进制内容不受影响
   （`bin/` 被 `.gitignore` 忽略，`--version` 只嵌 commit hash，而该提交**篡改不了**已构建二进制的版本串；
   核对方式：`git diff --stat <doc-commit>^ <doc-commit> -- modules/mcp_server/tools modules/mcp_server/tests` 为空）。

**结论（写入纪律建议）**：不要在报告里预先写下「本提交的 sha」——提交号只有提交后才能确定。
正确做法是：**先提交、再写/修报告的提交号、最后重建并复跑门**；本报告 §0 的 `a8210611cf` 即最终值。

7. **一次未能收敛的自引用（如实记录）**：第 6 步的「仅文档提交」本身也被写进了报告（先写成
   `a21bc49a40`），于是 amend → sha 变 `313505046f` → 报告又过期 → 再 amend → 又变……
   本批在这个环里走了 3 轮后停下并改掉做法：**报告不再引用「承载本报告的提交」自身的 sha**
   （§0 与 §11 已改成用 `git log --oneline -1` 的标题定位），环因此闭合。
   这条与 D86 的「结论必须可追溯」并不冲突：可追溯的是**被测代码**的锚点（`a8210611cf`），
   而「哪一条提交承载了这份报告」用标题定位即可，且该提交对代码零改动（`git diff --stat` 可证）。
