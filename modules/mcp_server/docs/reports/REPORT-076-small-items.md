# REPORT-076 — A：两处小尾巴（描述边界 + `UNCLASSIFIED` 派生）

> 任务书：`docs/tasks/TASK-076-small-items-and-audit.md` §A。手册：`docs/tasks/PLAYBOOK-group-port.md`。
> 本文件只覆盖 **§A**；§B（独立验收第 5 轮修复的复核）由另一个子代理执行，报告在 `REPORT-AUDIT-075.md` 一侧。
> 契约 **177 = 171 + 6**（条数未动）。本节 ① 只改描述、② 只改派生。
> 全部证据（绝对路径）：`F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task076\`。

## 0. status / commits

| # | commit | 一行说明 |
|---|---|---|
| 1 | **`e8c2ed5993`** | ① 三条描述边界（生成器 v1.22.0）+ C++/doctest 同步 + 契约重生成；② `mcp071` 的 `176` 改为派生 + 反向探针；三处证据助手脚本 + `evidence/task076/**` |
| 2 | **`e83de65d98`** | 本报告 + 最终二进制（`e8c2ed599`）的门证据覆盖 |
| 3 | 收尾（锚点记录） | 追加 `ANCHOR_STRUCTURAL_EQUIVALENT` 记录（§6）与 `gates/engine_anchor_post_report.txt` |

* 分支 `feature/mcp-server-module`；**未 push**。
* 最终门所绑定的二进制：`bin\godot.windows.editor.x86_64.console.exe --version` = **`4.8.dev.custom_build.e8c2ed599`**，`git rev-parse --short=9 HEAD` = **`e8c2ed599`**（D86：构建**在 commit 1 之后**重做，见 §5）。
* 9877：全程无监听、未占用/未杀/未重启；9888/9889 收尾已释放（`netstat` 无监听）。

---

## 1. ① 两条已定性边界写进相关工具描述

### 1.1 机制（走 `DESCRIPTION_OVERRIDES`，不手改契约）

`scripts/gen_renamed_contract.py`：

* `GENERATOR_VERSION` **1.21.0 → 1.22.0**（docstring 追加 v1.22 段）；
* 两个模块级共享字面量（与 `NODE_PATH_RULE_SENTENCE`(v1.19)、`_T059_SECTION_WRITE`(v1.18) 同一手法）：
  * `SCENE_TREE_ADDRESSABILITY_SENTENCE`（1 条描述用它）；
  * `TILEMAP_ATLAS_GAP_SENTENCE`（2 条描述共用同一句，二者不会漂移）；
  * `_T076_TILEMAP_GAP_REASON`（两条 `reason` 的共享事实段）；
* `DESCRIPTION_OVERRIDES` **追加 3 条**（全部 `mode=append`，默认值）：`get_scene_tree`、`tilemap_set_cell`、`tilemap_fill_rect`。
  生成器的 `startswith(<原文> + " ")` 守卫逐字检查原文仍在句首；`reason` 逐字引用被追加句所依据的**实测事实**（见 §1.3）。

**重生成（真实输出，`evidence\task076\gates\gen_renamed_contract.txt`）**：

```
gen_renamed_contract: output tools = 177
gen_renamed_contract: overrides = 36 (… description/get_scene_tree:append, … description/tilemap_set_cell:append, … description/tilemap_fill_rect:append …)
gen_renamed_contract: output sha256 = a5c59853c1e5a4913d600c663c8e972f058f7144869ec20337ab41b7a7bb17ea
gen_renamed_contract: self-checks = OK (lint 177/177, unique 177/177, disposition enum OK)
```

### 1.2 三处描述的表（逐条）

| 工具（契约名） | 迁移源 old_name | 原文（逐字，句首） | 追加的判别句 | 字节 |
|---|---|---|---|---|
| `editor_get_scene_tree` | `get_scene_tree` | `获取当前编辑场景的完整场景树` | `SCENE_TREE_ADDRESSABILITY_SENTENCE` | 42 → **898** |
| `editor_set_tilemap_cell` | `tilemap_set_cell` | `设置瓦片地图单元格` | `TILEMAP_ATLAS_GAP_SENTENCE` | 27 → **717** |
| `editor_set_tilemap_cells_in_rect` | `tilemap_fill_rect` | `填充瓦片地图矩形区域` | `TILEMAP_ATLAS_GAP_SENTENCE`（同一句） | 30 → **720** |

**(i) `editor_get_scene_tree` 的新描述**（append 后全文）：

> 获取当前编辑场景的完整场景树 本工具是“此刻编辑器侧可寻址什么”的权威：实例子场景内部的节点可能不出现在这棵树里，因为编辑器把 PackedScene 缓存成实例快照 —— 子场景改了以后，同一会话里既有的实例与新建的实例都仍带旧缓存（游戏进程从磁盘加载，因此能看到新节点）；要操作子场景新增的内部节点，就把 editor_add_node 的 parent_path 指向该实例、把它作为外层场景里实例下的子节点写（实测可寻址并可连信号），或者开一个新的编辑器会话让缓存重建；子场景本身的编辑永远应当先做，再做外层场景的实例化。这不是“各工具看不看得见不一致”：属性写工具与信号工具经同一个 MCPTools::find_node 解析路径，对同一路径给出同一结论，差别只在编辑器缓存。

它逐条覆盖了任务书的四个要求：**权威**（“可寻址什么的权威”）、**实例子场景内部节点可能不出现 + 原因**（PackedScene 实例快照）、**先改子场景再改实例**（“子场景本身的编辑永远应当先做”）、**不得声称各工具一致**（测量口径一致，差别在编辑器缓存）。

**(ii) 两处写工具的 TileMap 缺口句**（append 后全文，两条只在句首原文不同）：

> 设置瓦片地图单元格 写格子要求目标 TileMapLayer 的 TileSet 里已经存在一个 TileSetAtlasSource：project_create_resource 用 type=TileSet 只会造出一个空 TileSet（source_count=0，既没有 source 也没有 texture），而当前工具集没有任何“给 TileSet 添加 atlas source / texture / tile”的入口，所以在可预见的调用序列里本工具无法成功 —— 这是一处如实声明的能力缺口，不是本工具的缺陷；调用方要么在编辑器里手工建好带 atlas source 的 TileSet，要么在项目里自带一个含 source 的 .tres。TileSet 里没有该 source 时本工具以 -32602 拒绝，并在 data.suggestion 里点名它接受的参数。

**范围裁决（显式）**：缺口句只挂在**两个写工具**上。任务书写的是“TileMap 相关工具（`editor_set_tilemap_cell` 等）”，而事实是“**需要先存在** `TileSetAtlasSource`”——**读**工具（`editor_get_tilemap_info` / `_used_cells` / `_cell`）与 `editor_remove_all_tilemap_cells` **不要求** source 存在、也不会因此失败，给它们挂这句会让真正的调用方噪音化。读工具自己已能报 `source_count:0`（D5 实测），缺口由**会失败的**两个写工具声明。此裁决记录在此，供 §B 复核。

### 1.3 `reason` 逐字引用的事实（每条的出处）

* **(i)** 依据 `REPORT-075` §5 D4 的最小复现（脚本 `scripts/mcp075_d4_staleness.ps1`，9/9 PASS）：`player.tscn` 无子节点、`main.tscn` 实例化它后 `Player` 子节点数 = 0、`Player/Anim` → `-32001`；打开 `player.tscn` 加 `AnimationPlayer "Anim"` 保存后磁盘确实含 `Anim`，回 `main.tscn` 仍 `Player` 子节点 0、`Player/Anim` 仍 `-32001`；**新建**同文件实例同样 0；游戏进程（从磁盘加载）`/World/Player/{Body,Art,Anim}` 齐全；会话内绕法 `editor_add_node{parent_path:'Player'}` 后 `Player/Anim` 可寻址且 `editor_connect_signal` 成功 `connected:true, persisted:true`。机制 = 编辑器把 `PackedScene` 缓存成实例快照（§5 第 3 条）。**「不是工具口径不一」的出处**：三个工具都经同一个 `MCPTools::find_node`（`tools/tool_helpers.cpp:1417`），同一路径结论一致（§5 第 1 条）；round-5 的「属性写工具到得了 `Anim`」来自另一上下文 `docs/reports/evidence/task074/scripts-run/m4_anim.ps1:21`（先 `editor_open_scene res://scenes/player.tscn`，第 78 行才写 `path:'Anim'`，那是被编辑场景根的**直接子节点**，不是 `World/Player/Anim`）（§5 第 2 条）。裁决是**不改 `find_node`**（穿越缓存会改变所有编辑器工具语义、让读取产生写副作用，§6 第 4 条）→ 只声明边界。
* **(ii)** 依据 `REPORT-075` §6 D5：`project_create_resource{path:res://tiles/empty_tileset.tres, type:TileSet}` 返回 `{"properties_set":[],…,"type":"TileSet"}`；赋值前 `has_tile_set:false, source_count:0, sources:[]`；`editor_add_resource_to_node_property{tile_set}` / `editor_set_node_property{tile_set}` **都成功**；赋值后 **`has_tile_set:true`, `source_count:0`**（E8 的“赋值没落地”被证伪）；`editor_set_tilemap_cell{source_id:0,…}` → `-32602` `"The TileSet of this TileMapLayer has no source 0; it has: no source at all (add a TileSetAtlasSource first)"` + `data.suggestion`。缺口 = 无任何工具能创建/填充 `TileSetAtlasSource`（§6 结论：不改行为、按缺口记账）。

### 1.4 C++ 侧同步 + doctest（服务端读不到 `docs/`）

| 落点 | 改动 |
|---|---|
| `tools/editor_read_scene_inspector.cpp:747` | `ToolBuilder("editor_get_scene_tree", …)` 描述字面量 |
| `tools/editor_tilemap_write.cpp:532/:538` | `editor_set_tilemap_cell` / `editor_set_tilemap_cells_in_rect` 描述字面量 |
| `tests/test_mcp_server.h:19873/:19876` | B5 batch-3 doctest 的两条 `expect_description(...)` 期望值 |

**逐字（构建前就验证，`evidence\task076\gates\contract_cpp_diff.txt`）**：

```
MATCH editor_get_scene_tree            cpp bytes=898  contract bytes=898
MATCH editor_set_tilemap_cell          cpp bytes=717  contract bytes=717
MATCH editor_set_tilemap_cells_in_rect cpp bytes=720  contract bytes=720
MATCH project_list_scripts             cpp bytes=373  contract bytes=373
MATCH running_game_run_test_scenario   cpp bytes=571  contract bytes=571
RESULT: PASS (every checked tool's C++ description is the contract's description verbatim)
```

### 1.5 「只改描述」的证明（门① 之前、构建之前）

`scripts/mcp076_descriptions_only.py`（新增）在 `git HEAD` 契约与本工作树契约上逐键比对（`evidence\task076\gates\descriptions_only.txt`）：

```
old contract (git HEAD:…) sha256 = 6f654b64f87f60a5b0296e5a7a6b50f3b1a0af98c9ce8770ffe9f964172afbd6
new contract (worktree)     sha256 = a5c59853c1e5a4913d600c663c8e972f058f7144869ec20337ab41b7a7bb17ea
[PASS] entry count unchanged: old=177 new=177
[PASS] tool name order unchanged (177 names)
[PASS] every inputSchema byte-identical (differences: none)
[PASS] exactly the declared descriptions moved: ['editor_get_scene_tree','editor_set_tilemap_cell','editor_set_tilemap_cells_in_rect']
[PASS] 三条都是 append-only（原文逐字为前缀）
[PASS] _meta 差异仅 generator_version + overrides
[PASS] generator_version 1.21.0 -> 1.22.0；overrides 33 -> 36
[PASS] 新增 override 记录恰为三条 description/append；无既有记录被删除或改动
RESULT: PASS (the contract moved by descriptions only)
```

**C++ 侧也只动了描述行**：`git diff -- modules/mcp_server/tools` 只涉及两个文件，且每条 `+`/`-` 都是 `ToolBuilder(..., String::utf8(R"desc(…` 描述字面量（全文见 `evidence\task076\git_diff_tools_descriptions.patch`）；`git diff --stat` 中该二文件分别为 `2 +-` 与 `4 +-`。

### 1.6 红相位（当场保存）

* **描述同步的红相位**（`red_phase_contract_vs_head_cpp.txt`）：用 `git show HEAD:` 取改动前 C++ 字节，与新契约比：

```
RED-PHASE-MISMATCH editor_get_scene_tree            HEAD cpp bytes  : 42   / NEW contract : 898
RED-PHASE-MISMATCH editor_set_tilemap_cell          HEAD cpp bytes  : 27   / NEW contract : 717
RED-PHASE-MISMATCH editor_set_tilemap_cells_in_rect HEAD cpp bytes  : 30   / NEW contract : 720
RESULT: PASS (the pre-change C++ does NOT carry the new descriptions, so gate 1 would be red before the sync)
```

（该脚本退出码 = 0，语义是“红相位确实为红”；见文件内 `RESULT` 行。）

---

## 2. ② 清掉两行 `UNCLASSIFIED`（`176` → 派生）

### 2.1 红相位（改动前，当场保存）

`evidence\task076\red_phase_check_hardcoded_counts.txt`：把 `git show HEAD:` 的**改动前** `mcp071_gate2_live_evidence.ps1` 逐字节重放进**同一个**检查器（`--root` 指向 F: 盘上的临时根，避免跨盘 `relpath` 崩溃）：

```
BUCKET UNCLASSIFIED = 2
UNCLASSIFIED scripts/mcp071_gate2_live_evidence.ps1:192 [176] (($union.Count -eq 176) -and ($missingFromLive.Count -eq 0) -and ($extraInLive.Count -eq 0))
UNCLASSIFIED scripts/mcp071_gate2_live_evidence.ps1:266 [176] Write-Host 'GATE 2 LIVE EVIDENCE PASS (176 contract entries live, …)'
RESULT: FAIL (2 unclassified line(s))
```

退出码实测 **非 0**（同一命令用 `&&`/`||` 判定：`RED_EXIT_NONZERO`）。

### 2.2 修法（**不放松断言**）

| 行 | 改前 | 改后 |
|---|---|---|
| `:192` | `(($union.Count -eq 176) -and …)` | `(($union.Count -eq $contractNames.Count) -and …)` |
| `:266` | `Write-Host '…(176 contract entries live…)…'` | `Write-Host ('…({0} contract entries live…)…' -f $contractNames.Count)` |

`$contractNames` 是脚本自身在 `:152-154` 从 `docs/tools_list.renamed.json` 读出的集合——**派生自断言所关于的那件工件**，不是另一个写死的数。断言强度不减：`G208` 仍同时检查**大小**与**两个集合方向**（missing / extra）；PASS 行改为插值同一派生值。检查 id 里的 `176` 一并去掉（`G208_live_union_equals_the_contract_entries`，该处 `176` 因后接下划线本就不被扫描器识别，属文字卫生）。

### 2.3 反向探针（新增 `scripts/mcp076_gate2_union_count_reverse_probe.ps1`，**纯 ASCII**）

`evidence\task076\gates\union_count_reverse_probe.txt`（**9/9 PASS，exit 0**）：

```
[survey:stale]   exit=1 (expected 1) line=($u.Count -eq 176)
[survey:derived] exit=0 (expected 0) line=($u.Count -eq $contractNames.Count)
[PASS] old_G208_union_count_is_176                              value=False
[PASS] new_G208_union_count_is_derived                          value=True
[PASS] new_G208_size_term_separates_the_mutated_union           value=False（union 多一个名字）
[PASS] new_G208_still_has_the_missing_and_extra_half            value=True
[PASS] script_carries_the_derived_comparison                    value=True（在真文件上求值）
[PASS] script_no_longer_compares_against_the_literal            value=True（`-eq 176` 已消失）
[PASS] script_passing_line_is_derived_too                       value=True
[PASS] survey_flags_the_bare_literal_and_accepts_the_derived_spelling  value=True
[PASS] survey_exits_0_on_the_real_tree                          value=True
probes=9 failures=0
```

要点：①旧字面量在今日契约上**为假**（177）；②新派生式**为真**；③在**变异输入**（union 多一个契约里没有的名字）上**为假**，故非恒真式；④**检查器没有变瞎**——同一个检查器对「裸字面量」仍 exit 1、对派生拼写 exit 0（用 F: 盘上的两个临时根实测，跨盘 `--root` 会因 `os.path.relpath` 抛异常，探针脚本内已注明）。

### 2.4 检查器结果（最终树）

```
BUCKET UNCLASSIFIED = 0
BUCKET total        = 157
RESULT: PASS (every occurrence of 171/173/175/176/152/72/153 is classified; none is UNCLASSIFIED)
```

退出码实测 **0**（`&&`/`||` 判定：`HARDCODED_EXIT_ZERO`）。

---

## 3. 门（全部自跑；绑定二进制 `4.8.dev.custom_build.e8c2ed599`，源码 == commit `e8c2ed5993`）

| 门/检查 | 命令 | 结果（证据文件，均在 `evidence\task076\gates\`） |
|---|---|---|
| **第 0 步 构建** | `modules\mcp_server\scripts\build_local.cmd -Force`（cmd 启动，串行，不抑输出） | `EXIT_CODE=0`；`--version` = `4.8.dev.custom_build.e8c2ed599` == `rev-parse --short=9 HEAD` |
| **门①** | `scripts\check_contract_subset.ps1 -Group editor_read_scene_inspector` | **3/3 PASS**；`contract 177`、editor `154`、game `73`、`editor_get_scene_tree: name=True description=True inputSchema=True`、`guard_user_port_9877 pid_before=-1 pid_after=-1` → `gate1_editor_read_scene_inspector.txt` |
| **门①** | 同上 `-Group editor_tilemap_write` | **3/3 PASS**；`editor_set_tilemap_cell`/`_cells_in_rect`: 三字段全 True；两端口均“correctly absent”于 game → `gate1_editor_tilemap_write.txt` |
| **门②** | `mcp075_live_evidence.ps1 -Phase after`（9888/9889，三类请求 + 跨工具链写→读→sha） | **26/26 PASS**，`failures: 0`；含 `-32602` 四类拒绝、`-32001`+`suggestion`、`max_bytes` 省略/恢复、`write→read` 三方 sha、D4/D5 现场 → `gate2_live_evidence_after.txt` |
| **门③** | `--headless --test --test-case="[MCPServer]*"` | exit **0**：`348 | 348 passed | 0 failed`、`24223 | 24223 passed` → `gate3_doctest_mcpserver.txt` |
| **门④** | `--headless --test` | exit **0**：`1774 | 1774 passed | 0 failed | 3 skipped`、`448470 | 448470 passed` → `gate4_full_regression.txt` |
| **门⑤** | `scripts\accept_m1.ps1` ×2 | **23/23 ×2**；两次 `implemented tools = 154 / 73; contract = 177`；`tool_names` **177 条逐字一致**（names sha256 `276f162c94fb569b482cd1c5d67dff3612f99017190f450c2a936969665aa3ee`，与 `REPORT-075` 记录**同值**），`accept_m1_inventory_compare.json` `verdict=PASS` → `accept_m1_run1/2.txt`、`accept_m1_inventory_compare.txt/.json` |
| **门⑥ 三段式** | `check_narrowing_points.py` / `--coverage` / `mcp031_gate6_coverage_probes.ps1` | exit **0 / 0 / 全 PASS**：`scanned=75 pinned=75`、`101/101 checks passed`、`B1b_restored_byte_identical` + `worktree_clean_of_probes` → `gate6_*.txt` |
| 契约 177 = 171+6 | `check_tool_groups.py --check-completeness` | exit **0**：`ASSERT 171 + 6 = 66 + 105 + 6: PASS`、`every one of the 177 contract names …: PASS` → `groups_completeness.txt` |
| ADDED 清单一致 | `check_tool_groups.py --added` | exit **0**：`manifest = contract _meta.added_tools`（6）、`channel/verb derived agree: PASS` → `groups_added.txt` |
| 生成器版本 | `check_tool_groups.py --generator-version` | exit **0**：`GENERATOR_VERSION == _meta.generator_version == source.generator_version: PASS (1.22.0)` → `groups_generator_version.txt` |
| 退出码传播 | `check_exit_propagation.py`（+ `--probes`） | exit **0 / 0**：`EXIT-CODE PROPAGATION CHECK PASS`、探针全过 → `exit_propagation.txt`、`exit_propagation_probes.txt` |
| 恒真式扫描 | `check_tautologies.py`（+ `--probes`） | exit **0 / 0**：`TAUTOLOGY CHECK PASS` → `tautologies.txt`、`tautologies_probes.txt` |
| 硬编码普查 | `check_hardcoded_counts.py` | exit **0**：`UNCLASSIFIED = 0` → `hardcoded_counts.txt` |
| **D86 锚点** | `check_engine_anchor.ps1 -VersionText 4.8.dev.custom_build.e8c2ed599` | exit **0**：`ANCHOR_JUDGE VERDICT=ANCHOR_EQUAL`（`ANCHOR=22c33ee2f`→`e8c2ed599`、`HEAD=e8c2ed599`、`diff_count=0`）→ `engine_anchor.txt`（收尾记录见文末） |
| 契约/C++ 逐字（构建前） | `mcp068_contract_cpp_diff.py` | exit **0**：5/5 MATCH → `contract_cpp_diff.txt` |
| 定性边界/派生复核 | `mcp076_descriptions_only.py` / `mcp076_gate2_union_count_reverse_probe.ps1` | exit **0 / 0**（18/18 PASS / 9/9 PASS） → `descriptions_only.txt`、`union_count_reverse_probe.txt` |

**收尾**：`git status --short` 仅剩既有未跟踪物（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`）；9877 全程未碰；9888/9889 已释放。

---

## 4. 指纹（“全部指纹”，`evidence\task076\contract_fingerprint.txt`）

```
SHA256 tools_list.renamed.json    a5c59853c1e5a4913d600c663c8e972f058f7144869ec20337ab41b7a7bb17ea (163520 bytes)
SHA256 tool-rename-map.json       2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd (70917 bytes)   [未动]
SHA256 tool-groups.json           0cfcac80f0d999fa7db713ae48f43febe96ae52e2c93633257eeed00ffdfbfac (5682 bytes)    [未动]
SHA256 tool-groups-b2.json        14eba00016c00bff914bb39aff9cfb5f01e375a43fa2ff5038d69bdedfc8b75d (11623 bytes)   [未动]
SHA256 tool-groups-b3.json        d3422a6e3b1213a1fd356ce3dbae0e789200268b4d231337beb40ed5d25b956a (8526 bytes)    [未动]
SHA256 tool-groups-b4.json        d95d7d9e793a11aa56ccb66513051ec446e94725316ef3f54dfc28cf4f40a708 (3060 bytes)    [未动]
SHA256 tool-groups-b5.json        85bb783e29e6e02879e5c60769bdf0ffcc60a9fa2c9ad6cea8fde43acf2799fb (12209 bytes)   [未动]
SHA256 tool-groups-added.json     72d0c8ae7589b401dd56e3147bdfbb51c677512372ea5832aafc6b2b18a56c8d (9478 bytes)    [v1.22 版本串]
SHA256 gen_renamed_contract.py    e48b0cbfd632643f07110edf903387165791a131498b2379852369910e214620 (163303 bytes)
SHA256 check_rename_map.py        525798c76ece912787ef4efb0f343635b6bdfd0d462d4bad68cb3d8782e240fc (16500 bytes)   [未动]

contract: entries=177  _meta.count=177  added_count=6  overrides=36  generator_version=1.22.0  order_normative=False
```

契约 sha 只移动**一次**：`6f654b64…`（TASK-075 基线） → **`a5c59853…`**。

---

## 5. deviations / 风险 / next step

1. **构建顺序（D86）**：commit 1 落盘后，重做 `build_local.cmd -Force`（版本哈希随 HEAD 走），使二进制自报 `e8c2ed599` 并与 HEAD 相等；**所有门都在这次重建后的二进制上重跑**（① ② ③ ④ ⑤ ⑥ 全部重跑并覆盖证据）。没有这一步，锚点会是 `ANCHOR_STALE_COMPILED`（编译输入在 diff 里）——这是 TASK-071/072 记录的既有陷阱。
2. **新增 3 个助手脚本**（任务书未逐字要求，但门与反向探针需要）：`scripts/mcp076_descriptions_only.py`、`mcp076_gate2_union_count_reverse_probe.ps1`（纯 ASCII）、`mcp076_accept_inventory_compare.py`。三者都通过 `check_exit_propagation.py`、`check_tautologies.py`、`check_hardcoded_counts.py`。
3. **扩展 `scripts/mcp068_contract_cpp_diff.py`**：原实现的正则只认 `ToolBuilder(..., String::utf8("…"))` 的普通字符串形式，而三条 B5 注册用的是 `String::utf8(R"desc(…)desc")` 原始字符串形式——不扩展就**无法**在构建前验证这三条（其 docstring 本就声明 `CHECKED` 是“append-only, one line”，本次只追加 matcher）。matcher 的扩展不改变已检查工具的结果（5/5 MATCH）。
4. **TileMap 缺口句只挂两个写工具**（§1.2 的范围裁决）：读工具不因缺 source 失败，故不挂。
5. **发现（未修，属下一批）**：`mcp071_gate2_live_evidence.ps1` 的 `G204`（`153`）/`G207`（`72`）在今日端点上已过期（实测 editor `154` / game `73`）。它们被普查归入 `LIVE` 桶（“随每个已实现组移动”），**不是**本次的 `UNCLASSIFIED`，故未在本批改动；但**若有人直接运行该脚本，它会红在 G204/G207**。这两个数**无法**从契约文件派生（契约不分端点），需要由 `tool-rename-map.json` 的 `scope` + 两个清单派生——建议下一批把该脚本的端点计数也改为派生，或按 TASK-071 的语境标为历史证据不再作为门。
6. **未改动**：`docs/tool-rename-map.json`、五个批次清单、`docs/tools_list.renamed.json` 的 `inputSchema`（一条未动）、契约条数（177）。
7. **未 push**；未安装依赖；未访问 `100.105.152.101:18080`。

---

## 6. 锚点与收尾（D86）

* 门时锚点（**实测**）：`ANCHOR_EQUAL`，`ANCHOR=22c33ee2f`→重建后 `ANCHOR=e8c2ed599`、`HEAD=e8c2ed599`、`diff_count=0`、`RESULT PASS`（`gates\engine_anchor.txt`）。
* 本报告（与刷新后的证据）提交后 HEAD 前移到 **`e83de65d98`**；同一二进制（`anchor=e8c2ed599`）的判据实测为：

```
ANCHOR_JUDGE VERDICT=ANCHOR_STRUCTURAL_EQUIVALENT
ANCHOR_JUDGE ANCHOR=e8c2ed599 ANCHOR_REPORTED=e8c2ed599 HEAD=e83de65d9
ANCHOR_JUDGE DIFF_COUNT=8 SAFE_COUNT=8 RED_COUNT=0
ANCHOR_JUDGE RESULT PASS
```

即：8 个 diff 文件全部落在“已声明非编译”白名单内（本报告 + 7 个证据文件，均为 `docs/**`），**没有编译输入**，故 `STRUCTURAL_EQUIVALENT` 成立、`STALE_COMPILED` 不成立。这条记录按 TASK-072 / `REPORT-075` 的同一格式保留（`evidence\task076\gates\engine_anchor_post_report.txt`）。
