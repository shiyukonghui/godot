# REPORT-AUDIT-M4e — 第五次独立验收：M4 收口（D1–D6 闭合）+ 顺手性 + 报告矛盾裁决

> 独立验收方：未参与任何实现；**未采信**任何 `REPORT-*`（含 `REPORT-AUDIT-M4{,b,c,d}`）与决策者结论。
> 全部结论来自**本轮自己跑出的证据**。任务书：`docs/tasks/TASK-AUDIT-M4e.md`。
> 报告为**新增文件**；未修改任何被跟踪文件，未做任何 git 写操作（分支/索引/历史），未占用/杀/重启 9877。

---

## 0. 开工与基准

| 项 | 值 |
|---|---|
| 分支 / HEAD | `feature/mcp-server-module` / `9f2b2e484e1a4decbb2a8e37f33b7d160c95a0ee`（short `9f2b2e484e`） |
| 重建 | `modules/mcp_server/scripts/build_local.cmd -Force`（`tests=yes`，scons 输出未抑制、未并发） |
| 重建退出码 | `0`；日志 `%TEMP%\mcp_server_build_local.log` sha256-16 `d3edb3d0c0afb456` |
| `--version` | `4.8.dev.custom_build.9f2b2e484` == `git rev-parse --short HEAD` ✔ |
| 端口 | 开工/收尾两次实测 **9877 → PID 36392**（用户 Godot 4.7.1-mono，全程未动）；测试仅 9888/9889（E-10 另用 19890…19893 与临时高位口）；收尾仅剩 9877 一个监听、无孤儿 godot 进程 |
| 工作树 | 收尾 `git status --porcelain` 仅 4 个既有未跟踪物：`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`；`git diff --stat` 为空 |
| 临时目录 | `%TEMP%\audit-m4e\`（另用各脚本自己的 `%TEMP%\task0xx-*`） |

**验收方自己的脚手架（4 个自写脚本，纯 ASCII）**：`own_gate6_probes.ps1`（门⑥ 自造反例）、
`own_live_probes.ps1`（自写 scratch 工程上的 D1/D3/D4/D5/D6 + 零手术链）、`own_d3_game.ps1`（游戏侧 usage 位真值）、
`diff_contract.py`（无 override 基线结构化 diff）。
**本轮自己跑过的既有证据脚本（21 个）**：`gate6_a/b/c`（python ×3）、`mcp031/mcp032/mcp030/mcp025/mcp027/mcp028/mcp029/mcp026/mcp024a/mcp021/mcp022/mcp023/mcp024b`、
`check_contract_subset.ps1 ×4`、`accept_m1.ps1 ×2`、`--headless --test`（MCPServer 过滤与全量各一次）。

---

## 1. verdict（按任务书的六类）

| 类 | verdict | 一句话依据 |
|---|---|---|
| **D1–D6 闭合** | **pass** | D1 端到端链（写活动场景→别的工具读到新值→save→文件含新值）22/22 + 我方 53/53；D2 门⑥ 三段 + 自造五探针全红 + 位移不假红；D3 两端点零标签泄漏、整包大小写不敏感可解析；D4 immediate/deferred 双入口 `-32602` 且已声明参数不误拒；D5 零命中不出现 `Applied`；D6 描述与线上形态一致且 `path` 原样喂回成功 |
| **报告矛盾裁决** | **pass（有裁决）** | `REPORT-025` 成立；`REPORT-032` §next_step 第 2 条（`vector_component_hint` 返回空串/仍未修）**与当前树、与它自己 §3 的同一段观测、与线上往返证据三处矛盾**；**不存在两套并行分发表**；实现**不需要修**，需要的是 `REPORT-032` 的 append-only 勘误（详见 §3） |
| **契约与 override** | **pass** | `_meta.overrides` = 14（11 description + 3 inputSchema，与生成器声明集合逐对相等）；生成器重生成到临时文件与跟踪文件**逐字节相同**（sha256 `bd892be5…`）；结构化 diff 证明除这 14 对与 `_meta.overrides` 外**没有任何别的改动** |
| **顺手性** | **pass（2 条 low 观察）** | E-10 自己抓到子进程 cmdline、§23.4 19×2 两端点、§23.5 三形态、E-9/E-6、E-2、G-1、G-3 全部复现；自写零字符串手术链 4 步全 `code=0` 且调用方字符串处理 0 次；另报 2 条 low（见 defects 2/3） |
| **五形态静默错值** | **pass** | 自跑 `mcp021`(74 行 PASS)/`mcp022`(90)/`mcp023`(218) 0 FAIL；抽出 **≥25 例**拒绝证据，每例都同时具备 §20.5 的四条件（`-32602` + 回显有限 + 落盘无 inf/nan + 另一读工具读到旧值） |
| **门与端口** | **pass** | 门① 4 组 exit 0（并集 91/53，113 implemented）；门③ `222/222` 0 failed；门④ `1648/1648` 0 failed；门⑤ ×2 `22/22` 且两次 PASS 清单 `Compare-Object` diff=0；门⑥ 三段全绿；9877 前后同 PID，无孤儿 |

**总 verdict：pass**（4 条 low/文档级缺陷见 §8，均不构成 D1–D6 或六道门的闭合失败）。

---

## 2. A. D1–D6 逐条闭合（全部我自己重跑的）

### D1 活动编辑场景「真的写进去」
自跑 `mcp030_live_open_scene_write_evidence.ps1`：**22 checks / 0 failed**（`summary.json` sha256-16 `c8ec65c975de03e5`），
关键链路与值（脚本原始输出）：

* 混合调用 `project_set_node_property_across_scenes{type:Node2D, property:position, value:{x:3,y:4}, path_filter:'res://scenes', force:true}`
  → `code=0, total_scenes=2, total_nodes=2`；活动场景条目 `{"mode":"live_open_scene_written","written":true,"persisted":false,"count":1}`，
  关闭场景条目 `{"mode":"offline_saved","written":true,"persisted":true}`。
* **另一个工具**读回活动场景（`editor_get_node_properties path='.' property=position`）读到**新值 `{x:3,y:4}`**（旧实现此处读回 `{1,2}`）。
* `editor_save_scene` → `{saved:true}`；`scenes/good.tscn` **文件里含 `Vector2(3, 4)` 且不再含 `Vector2(1, 2)`**
  （sha 由 `d0d1198656e3dd09dd53eabad7726d9ef4ae816c03e610f654e064335fd30482` 起算，脚本逐字节比对）。
* 关闭场景同一调用即落盘（`side.tscn` 含 `Vector2(3, 4)`，无需 save）。

自写脚本（`own_live_probes.ps1`，53/53，`own_live_summary.txt` sha256-16 `9526e02c746f8ea5`）在同一链上另加：

* `D1_another_tool_reads_7_8`：写 `{7,8}` 后由 `editor_get_node_properties` 读回 `{x:7,y:8}`；save 后 `main.tscn` 含 `Vector2(7, 8)`（字节读，非字符串拼接比较）。
* `D1_07_zero_node_live`（对抗）：`path_filter='res://scenes/main.tscn'` 但 `type='Control'`（该文件里没有这种节点）→ **条目根本不进 `scenes_affected`**，`total_scenes=0`，
  `message="No scene matched …: nothing was written."`，**没有出现 `mode=live_open_scene_written` + `count=0` + `written=true` 的「成功+未写入」组合**。
* 不变量 `INV_no_success_without_write`（对该轮收集到的全部 `scenes_affected` 条目）：`code=0 ∧ written=false ∧ mode≠dry_run` 的条目 **0**；
  `INV_dry_run_never_claims_written`：`dry_run ∧ written=true` **0**。
* `mode`/`written`/`persisted` 语义表与源码一致（`project_cross_scene_write.cpp:710-715`：`written=!dry_run`、`persisted=(!dry_run ∧ offline_saved)`），
  且顶层 message 对活动场景明说 **NOT on disk yet（要调 `editor_save_scene`）**，与实况（save 前文件仍是旧值）一致。

### D2 门⑥ 三段式 + 自造五探针 + 位移不假红 + 自己找新绕过
三段（**exit 0**，日志 sha256-16）：

| 段 | 命令 | 结果 |
|---|---|---|
| a | `python scripts\check_narrowing_points.py` | exit 0；`scanned=30 pinned=30`，`unannotated=0 unlisted=0 stale=0 moved=0`；PASS 行明写「declared set is bounded and probed」 (`gate6_a` `be6ce1d14dafee1b`) |
| b | `python scripts\check_narrowing_points.py --coverage` | exit 0；打印 **16 种已声明拼写** 与 **4 条 declared NOT covered** 边界（`gate6_b` `518ead5daa658e8e`） |
| c | `powershell … scripts\mcp031_gate6_coverage_probes.ps1` | **85/85 checks，exit 0**，0 `FAIL`（`mcp031` `5a08a2a6f58ee032`） |

**自造反例**（`own_gate6_probes.ps1`：先备份字节 → 追加探针 → 跑扫描器 → 逐字节还原；**全程不调用 git**）：

* M4d 五个探针 + `(real_t)1.0e300` 控制探针：**6/6 全红（exit 1）且被按预期 pattern 点名**
  （`lit_float_range` / `cast_static_float` / `ctor_color` / `ctor_vector3` / `ctor_color` / `cast_real_t`）。
* **位移不假红**：只追加 6 个空行 → **exit 0，`scanned=30 pinned=30`**（行号漂移本身不是失败）。
* **逐字节还原**：每个探针前后 `running_game_test_execution.cpp` sha256 均为 `022bd3dd9642bf42b007ebf2c7cf403ecc1e675c58f7382440e15b08fc341d44`；
  收尾 `git status --porcelain` 与开工**完全一致**（仅 4 个已知未跟踪物）。
* **找到 5 个新的可绕过拼写（缺陷，见 §8 D-M4e-1）**，全部 `exit 0`（扫描器看不见），且**都不在 `--coverage` 打印的 4 条边界列表里**：
  `= -1.0e300;`（一元负号）、`= (1.0e300);`（括号字面量）、`= 0x1p1000f;`（十六进制浮点字面量）、
  经 typedef 别名的 `real_t/float` 声明、`float arr[1] = { 1.0e300 };`（数组初始化）。
  （另测 `= (float)std::numeric_limits<double>::max();` **被 `cast_float` 抓到**，exit 1 —— 不是绕过，是我这条探针的预期写错了。）
* **当前树中该类拼写是否已存在**：对 `tools/**` 全量检索 `(real_t|float) NAME = - / =( / { - / 0x1p` 只命中 `tool_helpers.cpp:1136` 的**已标注闸门实现本身**（`G24-THE-GATE`）→ 这 5 个绕过目前是**潜在**缺口，不是已落地的错值。

### D3 标签过滤 + 大小写不敏感整包解析
* **引擎真值（自己在编辑器端点跑 GDScript 探针）**：`Node2D` 的 `Actor` 上 usage 带 `GROUP(64)/CATEGORY(128)/SUBGROUP(256)` 的条目 13 个，
  值条目 42 个（排除 `_` 前缀与 `script`）。
* 线上 `editor_get_node_properties{path:'Actor'}`（不给 `properties`）→ **键集合与引擎值集合完全相等**（42=42，missing=[] extra=[]），
  **13 个标签一个都没出现**（`leaked=0`，大小写敏感比较），属性对象内**没有只差大小写的重复键**（`Material`/`material` 冲突已消失）。
* **大小写不敏感解析**：PowerShell 5.1 `ConvertFrom-Json` 同时成功解析**整个 HTTP 信封**与 `content[0].text`；
  紧邻的**正对照**（手写 `{"Material":null,"material":null}`）**确实抛错** → 「能解析」不是解析器从不抛错的假象。
* **游戏侧同族**（自写 `own_d3_game.ps1`，游戏进程内 GDScript 探针给 usage 位真值）：`running_game_get_node_properties{node_path:'/root/Main/Actor'}`
  不带过滤器 → 27 键；**13 个标签 0 泄漏**；答案键全部是节点上真实存在的值条目（extra=[]）；整包 `ConvertFrom-Json` 成功。
  命名路径 `properties:['Material','material']` → 只回 `{"material":null}`，**不再产生大小写重复键**，标签名被跳过。
  *（该 27/42 的差集见 §8 D-M4e-2：15 个被省略的键**全部**既无 `PROPERTY_USAGE_EDITOR(4)` 也无 `SCRIPT_VARIABLE(4096)`（usage=0 或 2），是工具既有的 usage 位筛选，不是标签漏网。）*

### D4 未知参数 `-32602`（两条入口）+ 已声明参数不误拒
自写脚本原始响应：

* **immediate 入口**：`project_get_settings{filter:'display'}` →
  `{"code":-32602,"message":"Unknown parameter 'filter' for tool 'project_get_settings'","data":{"suggestion":"Accepted parameters of project_get_settings: prefix, include_default"}}`
  —— 码对、**点名**对、`data.suggestion` 列出被接受名。
* 多键：`editor_get_node_properties{path:'Actor', bogus_one:1, bogus_two:2}` → `-32602` 且消息同时点名两个（`Unknown parameters bogus_one, bogus_two`）。
* 正确拼写 `properties:['position']` 仍然 `code=0`（没有把合法调用误伤）。
* **deferred 入口**（9889，工具 `running_game_get_node_property_samples`，`pending_handler` 注册）：
  `{node_path, properties, nope:1}` → `-32602`，点名 `nope`，`suggestion="Accepted parameters of …: frame_count, frame_interval, node_path, properties"`；
  紧接着同样的合法参数（`frame_count:3, frame_interval:1`）→ `code=0` 且**真的跨帧回答了 3 个采样**（延迟通道未被打断）。
  源码两处入口都调用同一判定：`tool_registry.cpp:386`（`call_tool`）与 `:418`（`call_deferred_tool`），**在创建 deferred task 之前**。
* **已声明但工具不兑现的参数不被误拒**：`running_game_run_test_scenario` 的 schema 声明 `scene_path, steps`；
  只给 `scene_path` → `-32602 "Missing required parameter: steps"`，**不是 `Unknown parameter`**（门的规则只针对 schema 未声明的名字）。
  *mono 专属的那类在本构建（`module_mono_enabled=no`）结构性不可构造 —— 见 §9 `unconfirmed`。*

### D5 零命中措辞
`project_set_node_property_across_scenes{type:'Control', path_filter:'res://scenes'}` → `total_scenes=0 total_nodes=0 scenes_affected=[]`，
`message="No scene matched 'res://scenes': nothing was written. …"`：**不含 `Applied`**；事后两个 `.tscn` sha256 与调用前逐字节相同（零写入）。
自写脚本另验：单文件 `path_filter` 但类型零命中时同样 `total_scenes=0`、无 `Applied`、无条目（措辞瑕疵见 §8 D-M4e-3）。

### D6 描述 ↔ 线上形态一致、`path` 原样喂回
* `running_game_get_scene_tree` 线上描述 = 「获取运行中游戏的场景树结构」；线上答案 `tree.path = "/root/Main/Actor"`（SceneTree 绝对）。
* `running_game_get_node_properties` 线上 `description` **含 `/root/Main/Actor`** 并明写「两种写法都接受：相对场景根（如 Actor、A/B）或绝对路径（如 /root/Main/Actor）」，
  同时保留旧措辞（append 型 override，不是替换）。
* **原样喂回**：把 tree 返回的 `"/root/Main/Actor"` 不做任何处理传给 `node_path` → `code=0` 且回 `{"node_path":"/root/Main/Actor","properties":{"position":{"x":7.0,"y":8.0}},"type":"Node2D"}…`；
  相对写法 `"Actor"` 同样 `code=0` 且解析到同一节点。
* 自跑 `mcp032`：**78 行 PASS / 0 FAIL**（`dbf17c1ae2936f01`），其中 D6 全组 PASS（线上描述、契约一致、两种写法、同一节点）。

---

## 3. B. 两条报告矛盾的**裁决**（本轮重点）

**裁决：`REPORT-025` 的「已补齐 `Vector4i`/`Rect2`/`Rect2i`，19 项 × 两端点往返通过」成立；
`REPORT-032` 的「TASK-024b 记录的两个写侧缺口仍未修（`vector_component_hint` 返回空串）」为假。不存在两套并行分发表；实现无需修，需要的是报告勘误。**

证据一：**源码**（当前 HEAD，工作树干净）

* `tools/running_game_node_write.cpp` `vector_component_hint()`：`VECTOR4I` → `"x","y","z" and "w"`（:249-250）；`RECT2`/`RECT2I` → `"x","y","width" and "height"`（:256-258）。**不是空串。**
* 同文件 `_vector_components()` 的 `VECTOR4I`(:354-359)/`RECT2`(:371-376)/`RECT2I`(:377-382) 分量表齐全；`vector_from_dictionary()` 的 `VECTOR4I`(:198-204)/`RECT2I`(:205-212)/`RECT2`(:213-222) 折叠分支齐全（提交 `a95b824053`，TASK-025 E-3）。
* 读侧 `tool_helpers.cpp` 的 `RECT2`(:157)/`VECTOR4I`(:195)/`RECT2I`(:204) 与写侧**同集合**；`project_setting_write.cpp:110-112` 的 `Vector4i/Rect2/Rect2i` 名→类型表也齐全。
* **不存在陈旧第二表**：`tools/**` 内所有 `"width"/"height"` 字面量的出现处只有 `running_game_node_write.cpp`（已更新的分量表与折叠）与 `tool_helpers.cpp`（读侧序列化），没有第二份用于写侧分发的表。

证据二：**线上往返（我自己跑，两端点）** `mcp025_e3_writeside_evidence.ps1` → **110/110 checks，0 FAIL**（`99b1235ebb16c24b`）。原始响应：

* 编辑器 9888：读回 `v4i:{"w":4,"x":1,"y":2,"z":3}`（`B_editor_v4i_read_shape` PASS）→ **原样写回** `code=0, new_value={"w":4,"x":1,"y":2,"z":3}` → 再读 `{"w":4,"x":1,"y":2,"z":3}`（`B_editor_v4i_round_trip` PASS）；
  `rect_i` 同理 `{"height":40,"width":30,"x":1,"y":2}` 往返 `code=0`（`B_editor_rect_i_round_trip` PASS）。
* 游戏 9889：`D_game_v4i_read_shape/_round_trip`、`D_game_rect_read_shape/_round_trip`、`D_game_rect_i_read_shape/_round_trip` 全 PASS；
  `F_matrix_is_the_declared_19_entries` 与 `F_every_entry_is_writable` PASS（19 项两端点各自全绿）。

证据三：**TASK-024b 自己的 GAP 断言现在以 `code=0` 失败**——这是「已修」的**正向**证据。
我自跑 `mcp024b_ergonomics_batch2_evidence.ps1`：`66/68`，失败的恰是那两条（`d860ad799739fff2`）：

```
[FAIL] GAP_v4i_object_read_back_is_refused_by_the_write_side
       editor_set_node_property(v4i = the read-back object) -> code=0 message=''
[FAIL] GAP_rect_i_object_read_back_is_refused_by_the_write_side
       editor_set_node_property(rect_i = the read-back object) -> code=0 message=''
```

该断言原文是 `Check ... ((Get-ErrorCode $v4iBack) -eq -32602)`（`mcp024b…ps1:656`）——它断言「写侧拒绝」。
现在写侧**接受**（`code=0`），断言才失败。**「脚本仍红」= 缺口已闭合，而不是缺口仍在。**

证据四：**doctest** 直接断言 `vector_component_hint(VECTOR4I/RECT2/RECT2I)` 非空且逐字相等
（`tests/test_mcp_server.h:14846-14855`），门③ 自跑 `222/222 passed, 0 failed` 覆盖它。

**`REPORT-032` 为什么错（缺陷归属）**：它自己 §3 第 156-157 行已经记录了同一批 `GAP_*` 失败，并写明
「写成功而断言期望拒绝」——即**它已观测到修复**；但 §next_step 第 2 条却把 TASK-024b 当年的**残余缺口建议**
照抄成「仍未修」，从未重测。这不是实现缺陷，而是**报告里一条未经复测的陈旧结论**，
按 PLAYBOOK §7.3（证据被证伪要显式撤回，append-only 勘误允许且鼓励）应当补一条勘误。
**是否需修实现：不需要。** 需要修的是 `REPORT-032` 的措辞，以及决策层对「报告结论可被后续批次悄悄过期」的登记方式。

---

## 4. C. 契约与 override 纪律

1. **数 override**：`docs/tools_list.renamed.json` 的 `_meta.overrides` = **14** 条
   （`description`×11：`search_files`、`search_in_files`、`uid_to_project_path`、`project_path_to_uid`、`play_scene`、`get_game_node_properties`、`replay_recording`、`find_signal_connections`、`find_node_references`、`analyze_signal_flow`、`get_test_report`；
   `inputSchema`×3：`play_scene`、`replay_recording`、`get_test_report`）。生成器自报 `overrides = 14`，与文件**逐对相等**（自写脚本用未被改动的导入对象做集合比对：`difference: []`）。
2. **重生成逐字节比对**：`python scripts\gen_renamed_contract.py --out %TEMP%\audit-m4e\tools_list.renamed.regen.json` → exit 0；
   与跟踪文件 **sha256 完全相同**（`bd892be58e1f0321392904a29cab57d7f0097978aef4dc75d0b3d296eeb067cc`）→ **无手改**。
   生成器自带自检 `lint 171/171, unique 171/171, disposition enum OK`。
3. **结构化 diff（除 override 与指纹字段外没有别的改动）**：把生成器的两个 override 表清空后重生成一份「纯重命名」基线（`tools_list.baseline_no_overrides.json`，sha256-16 前缀 `9697289c…`），
   逐工具逐字段比较：**只有** `description` 差 11 个工具、`inputSchema` 差 3 个工具（与 14 对完全一致），
   `_meta` 逐键比较只有 `overrides`（14 vs 0）不同，`count/excluded/generated_by/generated_from/generated_from_sha256/generator_version/map_path/map_sha256/merged/order_normative/tool_count_in` **全部 same=True**；171 条名字集合相等。
4. 契约文件与三个生成器本批**未被写过**（工作树 `git diff --stat` 为空）。

---

## 5. D. 顺手性与行为（抽样复核，全部我自己重跑）

| 条款 | 自跑脚本与结果 | 关键证据 |
|---|---|---|
| **E-10 端口注入** | `mcp024a` **31/31**（`4fcb8995be2e5403`） | 自己抓子进程 cmdline：`pid 15996 command line contains --mcp-port=19890`，且该 pid 是响应里报的 pid；自动端口用例 cmdline = `… "--mcp-port=50394"`；在注入端口上跑游戏侧工具 `running_game_get_scene_tree` 成功；端口被占/等于编辑器端口**都被拒**（`busy_port_is_refused`、`editor_own_port_is_refused`、`no_game_started_by_refused_calls`） |
| **§23.4 双向闭合** | `mcp025` **19/19 × 两端点** | 见 §3 证据二；`F_matrix_is_the_declared_19_entries`/`F_every_entry_is_writable` PASS |
| **§23.5 `OBJECT`** | `mcp027` 全 PASS（`cdc1776e942c8ee2`） | `D8_chain_step2_unset_reads_null`（未设置 → `null`，不是 `{}`）、`D8_node_empty_object_is_-32602`（`{}` → 参数错误）、`D8_chain_step4_set_reads_the_type_path_shape` / `step5_read_shape_is_accepted` / `step6_reread_is_equal`（同形对象读→写→再读等价）、`step7/8`（写 `null` 后读回 `null`）；资源侧同组全 PASS |
| **E-9 截断** | `mcp026` **37/37**（`0d692d9ac4ebe2d0`） | `E9_7_environment_answers_a_truncation_marker`；两端点键集合等于引擎存储表（`E9_6`/`E9_11`） |
| **E-6 日志来源** | `mcp026` 同上 | `source=editor_log in_process=True`；`editor=True process=editor pid=65648`（与 9888 监听进程一致）；**游戏进程的行不混进编辑器答案**（`E6_12`，game pid 57160，GAME 标记在编辑器答案里为空） |
| **E-2 两进程路径一致** | `mcp027` | `E2_cli_two_process_paths_are_equal`、`E2_cross_process_responses_are_byte_identical`、`E2_run2_no_path_field_is_absolute` |
| **G-1 子属性路径** | `mcp028` **54/54**（`7b0f8b8f3835f25e`） | `position:y` 写 1→3 且读回 `{x:1,y:3}`；`v4.x` 写成功；shader 参数可写；越界 `position:y=1e300` **被拒且旧值不变**；缺段 `-32001` 点名、不可索引/畸形路径 `-32602` |
| **G-3 `clear` 非破坏性** | `mcp028` / `mcp029`（`4c847d99541be08f`） | 两次**不带 `clear`** 的读取返回**同一 sha256** 且文件仍在（`G3_two_clients_both_read_whole`：A/B 都 `total=2`，`file after A=True after B=True`）；只有 `clear:true` 才 `cleared:["editor_process","game_process_file"]` 并删除桥接文件；清空后诚实 `no_results:true, report_file_present:false` |
| **零字符串手术链** | 我自写 4 步链 + `mcp024a`/`mcp025`/`mcp026`/`mcp027` 各自的链 | 我自己的链：`running_game_get_scene_tree` → 取 `tree.children[].path` 原样 → `running_game_get_node_properties{node_path:<该值>}` → 把读回的 `position` **对象本身**作为 `value` 传给 `running_game_set_node_property` → 再读；四步全 `code=0` 且前后结构相同，**调用方字符串处理 0 次**（脚本里该值只做赋值传递，无任何 `Split/Replace/Substring/Trim`） |

以上脚本我逐个检查了 `[FAIL]` 行数：**0**。

---

## 6. E. 五形态静默错值（对抗抽样 ≥10 例）与延迟/事务/安全

自跑 `mcp021`(74 PASS)/`mcp022`(90)/`mcp023`(218) 均 **0 FAIL**。抽出（均为我自己跑出的原始证据，节选 id 与要点）：

| 形态 | 例（自跑证据） | 四条件 |
|---|---|---|
| ① 容器元素 | `C2_byte_element_300`（`300→44`）、`C2_byte_element_minus1`（`-1→255`）、`D2_int32_element_3e9`（`3e9→低32位`）、`E2_float32_element_1e300`（`→inf`）、`E2_float32_element_1e_minus300`（`→0`） | `-32602` + `result_is_null=True` + `project.godot` sha 前后相同 + 读回 `setting_before==setting_after` |
| ② 复合分量 | `G2_vector4_bad_component`（`value[0].x="abc"`）、`G2_vector4_missing_w`、`J1_component_float32_overflow_position`（`value.x`）、`J1_component_float32_overflow_modulate`（`value.b`）、`K5_add_nodes_batch_int32_component_refused`（`3000000000`） | 同上；`J2_component_in_range_still_writes` 证明**合法值仍写得进去**（不是一刀切拒绝） |
| ③ 标量成员 | `K1_set_property_batch_bool_string_refused`、`K2_…colour_string_refused`、`K3_add_nodes_batch_bool_refused_and_rolled_back`、`M6_task020_vector_string_grammar_still_refused`、`L1_modulate_unreadable_string/empty_string` | `-32602` + 场景 sha 相同 + 旧值仍在 + 批量 `batch_status=rolled_back` 且新增节点 `leaked=0` |
| ④ 专用 setter 路径 | `mcp023`（218 PASS，门⑥ 相关收窄点全部 `gated`/`pregated`/`safe`/`gate` 归类并有探针） | 与 `--coverage` 的 16 拼写集合一致，`scanned==pinned==30` |
| ⑤ 构建配置 | `build_is_single_precision`（本机单精度，`real_t`=float；`FLOAT32` 槽不参与 `#ifdef`）+ 门⑥ 的 `--coverage` 声明边界 | 仅源码级/单元级，双精度端到端**未验**（§9） |

**延迟/事务/安全（抽样）**：延迟通道我自己测了两条入口（未知参数即时 `-32602`、合法参数跨帧回 3 个采样）；
事务性有批量回滚（`K3/K4/K5` `rolled_back` + 泄漏 0）与跨场景「全成功/全回滚」预校验（源码 `project_cross_scene_write.cpp:428-570` + `mcp030` 的封闭场景落盘断言）；
安全面：E-10 的端口占用/自身端口拒绝、`outside_path_is_-32602`、`accept_m1` 的 413/431/非 UTF-8 body/半包/连接回收等 22 例全过。

---

## 7. F. 六道门与端口

| 门 | 命令（我自跑） | 结果 |
|---|---|---|
| ① 契约子集逐字 | `check_contract_subset.ps1 -Group {project_read_template, editor_node_read, running_game_observation, editor_node_write}` | **4 组全部 exit 0**；每组都断言并集：`implemented_union=91 tools (editor) / 53 (game)`，113 个 implemented 工具；`editor_9888_contract_subset` / `game_9889_contract_subset` PASS |
| ② 三类证据 + 跨工具链 | 上述 21 个证据脚本（成功/缺参/底层失败三类 + 多条跨工具链） | 见 §5/§6；`[FAIL]` 总数 0 |
| ③ 模块 doctest | `--headless --test --test-case=[MCPServer]*` | **`222 passed | 0 failed`**，`9255 assertions | 0 failed`（`18da04c18ebc60ab`，与 `REPORT-032` 引用的同一 sha 前缀一致 → 可复现） |
| ④ 全引擎回归 | `--headless --test` | **`1648 passed | 0 failed`**，`433537 assertions | 0 failed`（`3ecb153efd2d4c16`） |
| ⑤ 每批收口 | `accept_m1.ps1` 连跑两次 | 两次 **22/22**，`[FAIL]` 0；两次 PASS 清单 `Compare-Object -CaseSensitive` **diff=0**；摘要 `implemented tools = 91 / 53` |
| ⑥ 收窄点 | 见 §2 D2（三段） | exit 0 / exit 0 / 85-85，`scanned=30 pinned=30`，0 误报 |
| 端口 | 9877 前后 PID **36392→36392**；9888/9889 收尾均为空闲；`Get-Process godot*` 只剩用户那个 mono 进程 | 无孤儿；`--import` 全部 exit 0（首导 1 次成功） |

### 我方脚手架的两处自伤（如实登记，**不是**产品缺陷）
1. 我的批量驱动 `sweep.cmd` 以 LF 换行写入，`cmd.exe` 跳过了其中一行（`mcp030`），导致 `mcp030` 未在该轮执行 → 我据「无日志即无运行」发现并**单独重跑**了它（§2 D1 的 22/22）。
   后续 3 次 `check_contract_subset` 改为逐条前台执行。
2. 我给门① 传了不存在的组名 `node_read`（真实组名是 `editor_node_read`）→ 脚本以 exit 2 正常报「group not found」，**不是门失败**；据此改用 3 个真实组名重跑，全 exit 0。

---

## 8. defects（本轮发现，均不影响 §1 的 pass；如实列出）

1. **D-M4e-1（medium，门⑥ 覆盖边界未显式声明；潜在，非已落地错值）**
   `check_narrowing_points.py` 的 16 拼写集合对以下 **5 种「同一个 32 位 float 收窄」的拼写完全不可见**（我逐字节插桩实测 exit 0），
   而 `--coverage` 打印的 4 条 `declared NOT covered` 边界**并未包含它们**（只列了运行时隐式收窄、表达式推导、整数收窄、`tools/**` 之外）：
   `float x = -1.0e300;`、`float x = (1.0e300);`、`float x = 0x1p1000f;`、经 typedef 别名声明、`float arr[1] = {1.0e300};`。
   这违反 §22.3b 规则 6 的「未覆盖的边界必须**显式打印**，不得靠沉默暗示」。
   证据归属：`scripts/check_narrowing_points.py` 的 `PATTERNS` / `NOT_COVERED`。当前 `tools/**` 中该类拼写**不存在**（全量 grep 只命中已标注的闸门实现），因此是**闸门覆盖缺口**而不是线上错值。
   建议：把这 5 种拼写扩充进 `PATTERNS`（并各配「插入即 exit 1」探针），或至少逐条写进 `NOT_COVERED` 打印文本。
2. **D-M4e-2（low，D3 描述与同族一致性）** `running_game_get_node_properties` 的 `inputSchema.properties.properties.description` 写的是
   「不传则返回所有属性」，但枚举路径只答 `PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_SCRIPT_VARIABLE` 的子集：同一个 `Node2D` 上 **27/42**
   （省略的 15 个 = `name, owner, transform, global_position, global_rotation(_degrees), global_scale, global_skew, global_transform,
   unique_name_in_owner, scene_file_path, multiplayer, process_thread_group_order, process_thread_messages`，**全部 usage=0 或 2**）；
   而编辑器同族 `editor_get_node_properties` 不带过滤器答 42 个。**没有标签泄漏、没有大小写冲突、不是回归**（TASK-032 §3.D3 已声明该 usage 位筛选），
   但「所有属性」的自我描述与实际不符，且两个同族工具对「属性集合」的答案不一致（顺手性/可预期性）。
   证据：`tools/running_game_observation.cpp:196-214` 的 `wanted = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_SCRIPT_VARIABLE`；本轮 `own_d3_game.ps1` 实测。
3. **D-M4e-3（low，D5 措辞）** 当 `path_filter` 给的是**单个场景文件**、文件匹配上了但**该类型节点数为 0** 时，
   消息为 `No scene matched 'res://scenes/main.tscn': nothing was written. 'path_filter' names a directory that contains .tscn files, not a single scene file; check it and call again.`
   —— 后半句建议**不成立**（单文件过滤是被接受的，文件也确实匹配上了，只是没有该类型节点）。零命中「不写、不说 Applied」的核心判据是对的。
   证据：`project_cross_scene_write.cpp:742-743`；本轮 `own_live_probes.ps1` 的 `D1_07_zero_node_live` 原始响应（sha256 `35079542597be36f…`）。
4. **D-M4e-4（documentation，`REPORT-032` 结论过期，需勘误）** 见 §3：其 §next_step 第 2 条与当前树、与它自己 §3 的观测、与线上往返证据三处矛盾。
   **实现无需修**；按 PLAYBOOK §7.3 补 append-only 勘误，并把「报告结论可被后续批次过期」纳入决策日志的登记事项。

---

## 9. unconfirmed（区分「证据支持」与「推断」）

* **双精度构建**：本机只构建 `precision=single`（`build_local.cmd` 不传 `precision=`）。`FLOAT32` 槽的「任何构建都按 32 位判」目前是**源码级 + 单元级**结论，**未做双精度端到端**（与 DESIGN-DETAIL §22.2 的风险登记一致）。
* **mono 专属工具族**：本构建 `module_mono_enabled=no`，D4 里「已声明但工具不兑现」的用户可见拒绝路径（handler 侧、而非注册表侧）在本机**结构性不可构造**；我只验证到「注册表不误拒已声明名」（`scene_path` 用例）。
* **`mcp008` / `mcp014`**：既存红脚本（前者期望已变更的 `-32603`，后者需 mono 且用旧助手名），与 M4e 四条硬活无关，**本轮未作为判据**，也未重跑。
* **`mcp024b` 的 exit 1**：如上，是「缺口已闭合」的正向证据，但它使该脚本恒红 —— 属脚本时代错位，需一个收口批次（与 `REPORT-032` 的既有建议一致）。
* **`mcp011`（延迟通道专项证据脚本）本轮未重跑**：延迟通道的两条入口由我自写的探针覆盖（§2 D4），但 `mcp011` 里更细的时序/超时断言未复核。
* **`mcp016` 等需要改树/重建的对照实验**未跑（会与「不得修改跟踪文件」冲突）。

---

## 10. risks

1. **门⑥ 是有限集合保证，且集合仍在被绕过**：M4d 找到 5 种、本轮又找到 5 种（D-M4e-1）。若只靠门⑥ 变绿判定「没有新收窄」，会重复犯错；必须坚持「机器检查 + 代码审查（新增写值路径点名它过的闸门）+ 行为证据」三腿（§22.3b 规则 2）。
2. **报告会过期而没人撤回**：`REPORT-032` 的这条错误结论已经进入「下一步建议」，若照它开工会做一批无用功（TASK-025 已修的东西）。决策层需要一个「报告勘误 / 结论有效期」的轻量纪律（append-only 勘误行 + 在批次开工前用一条命令复测该结论）。
3. **同族工具答案集合不一致**（D-M4e-2）：调用方先在编辑器枚举、再在游戏里按名取值是可行的（命名路径不受 usage 位过滤），但「两边枚举集合相同」的直觉会落空，容易写出漏读的自动化。
4. **`build_local.cmd -Force` 的假绿纪律仍在**：本批我用了 `-Force` 并校验 `--version`==HEAD；任何后续批次若只用仓库根的 `build-m0.cmd`（不传 `tests=yes`）或编辑 `tests/*.h` 后不删陈旧 obj，仍会得到「门③/④ 变绿但新断言没跑」的假绿（R-5）。
5. **测试端口与用户端口的边界**：本轮 E-10 会临时占用 19890-19893 与高位自动端口；脚本虽已 `stop_scene`/`no_orphan_after_chain`/`test_ports_released` 自检，但这类用例越多，越需要收尾的「端口/进程清单」断言（我已按 `netstat` + `Get-Process` 复核：收尾只剩 9877/PID 36392）。

---

## 11. next_step_recommendation（交给决策者）

1. **接受本轮 verdict（pass）**，把 D1–D6 记为闭合；把 §8 四条作为下一批的输入（都不阻塞 M4 收口）。
2. **优先做两条零风险动作**：
   (a) 给 `REPORT-032` 追加**勘误行**（§next_step 第 2 条作废，说明 `Vector4i`/`Rect2`/`Rect2i` 写侧已于 TASK-025 `a95b824053` 闭合，并指向本轮 §3 的三条证据）；
   (b) 把 D-M4e-1 的 5 种拼写**要么**并入 `PATTERNS`（推荐，附探针）**要么**写进 `NOT_COVERED` 打印文本，二选一即可消除「沉默边界」。
3. **可选的小批次**：修 `mcp024b` 的两条 `GAP_*`（改成「已知缺口已闭合」的正向断言或移出 exit 判据）、修 D-M4e-2 的自我描述（`不传则返回所有属性` → 说明 usage 位筛选）、修 D-M4e-3 的措辞。
4. **不建议**在 M4 收口前再引入新的收窄拼写或属性枚举语义变更；若要做，按 §22.3b 规则 4 在报告里逐条列「新增点 × 经过的闸门 × 证据」。
5. **M5（hof-rs 集成）开工前**，先声明「报告结论的有效期/复测命令」这一轻量纪律，避免再出现 `REPORT-032` 式的陈旧结论被当成待办。

---

## 附：本轮证据文件与 sha256（前缀 16）

| 内容 | 路径 | sha256-16 |
|---|---|---|
| 重建日志 | `%TEMP%\mcp_server_build_local.log` | `d3edb3d0c0afb456` |
| 门⑥ a/b/c | `%TEMP%\audit-m4e\sweep\gate6_{a,b,c}.out.log` | `be6ce1d14dafee1b` / `518ead5daa658e8e` / `78f10377e75b857a` |
| 门⑥ 探针脚本（官方） | `…\mcp031.out.log`（85/85） | `5a08a2a6f58ee032` |
| 门⑥ 自造反例 | `%TEMP%\audit-m4e\gate6\own_gate6_summary.txt`（50/52，2 条是我探针预期写错） | `89ba8046dc0f9556` |
| D1（官方） | `%TEMP%\task030-live-open-scene\summary.json`（22/22） | `c8ec65c975de03e5` |
| D1/D3/D4/D5/D6（自写） | `%TEMP%\audit-m4e\own\own_live_summary.txt`（53/53） | `9526e02c746f8ea5` |
| D3 游戏侧 usage 真值 | `%TEMP%\audit-m4e\own\evidence\G3_01_usage_probe.response.json` | 见 `own_d3_game.ps1` 输出 |
| D3/D4/D6（官方） | `%TEMP%\audit-m4e\sweep\mcp032.out.log`（78 PASS/0 FAIL） | `dbf17c1ae2936f01` |
| 往返 19×2 | `%TEMP%\audit-m4e\sweep\mcp025.out.log`（110/110） | `99b1235ebb16c24b` |
| TASK-024b GAP 正证 | `%TEMP%\audit-m4e\sweep\mcp024b.out.log`（66/68，失败即那两条，`code=0`） | `d860ad799739fff2` |
| 静默错值 | `mcp021/022/023.out.log`（74/90/218 PASS，0 FAIL） | `61a821461494c16c` / `156725c49f7456ff` / `f05e7ca9a9904fa4` |
| 顺手性 | `mcp024a/026/027/028/029.out.log` | `4fcb8995be2e5403` / `0d692d9ac4ebe2d0` / `cdc1776e942c8ee2` / `7b0f8b8f3835f25e` / `4c847d99541be08f` |
| 门① | `%TEMP%\audit-m4e\sweep\gate1_*.out.log`（4 组 exit 0） | `4cc0e021a66a30ee`（editor_node_read） |
| 门⑤ ×2 | `…\gate5_run{1,2}.out.log`（22/22 ×2，清单 diff=0） | `1f0ea1bf5df66bbe` / `1cc2f4b355fc0467` |
| 门③ / ④ | `…\gate3.out.log` / `gate4.out.log` | `18da04c18ebc60ab` / `3ecb153efd2d4c16` |
| 契约重生成 | `%TEMP%\audit-m4e\tools_list.renamed.regen.json` | `bd892be58e1f0321…`（与跟踪文件逐字节相同） |
| 契约结构化 diff | `%TEMP%\audit-m4e\tools_list.baseline_no_overrides.json` + `diff_contract.py` | `9697289c78ccd719`（基线） |

> 全部证据脚本/探针均为**纯 ASCII**；响应体一律 `curl.exe -s -o <file>` 落盘后取 sha256，请求体一律 `ConvertTo-Json` + `--data-binary @file`，
> 未用 `Out-File`/管道承载响应体；临时实验（门⑥ 探针）在**不改动任何跟踪文件净内容**的前提下完成，并在收尾用 `git status --porcelain` 与逐字节 sha256 双重证明。
