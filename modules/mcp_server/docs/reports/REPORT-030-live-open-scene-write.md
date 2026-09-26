# REPORT-030 — 活动编辑场景的写入真的发生（D1）＋ 零命中不再宣称「已应用」（D5）

- **status**：完成（D1 选择「方案①真写活节点」；D5 选择「显式说明无匹配」）。全部五道门 + 门⑥ 自跑通过；
  TASK-028/TASK-029 证据脚本重跑无回退；TASK-018 脚本有 **1 条与本次改动无关的历史断言失败**（见 §10.3）。
- **commits**：
  - `545060f25e` TASK-030 D1+D5: write the live edited scene, and say when a scene was not written
    （`tools/project_cross_scene_write.{h,cpp}` + `tests/test_mcp_server.h`）
  - `b6203ba2b7` TASK-030: live evidence script for the open-scene write chain (D1, D5)
    （`scripts/mcp030_live_open_scene_write_evidence.ps1`）
  - 本报告为第三条提交（见文末 git log）。
- **构建**：`modules/mcp_server/scripts/build_local.cmd -Force`（`tests=yes`），串行、不抑制输出；
  `--version` 自报 `4.8.dev.custom_build.be62ea7ec` == `git rev-parse --short HEAD`（`be62ea7ec9`，开跑前核对过两次）。

---

## 1. 选了哪个方案，以及理由

**选了方案 ①（真的写活节点）**，不选 ②（诚实拒绝）。理由（第一性原理：调用方要的是「把值写进去」，不是「被拒绝」）：

1. **工具本来就承诺了这件事**。它的契约（`docs/tools_list.renamed.json` 与迁移源 `batch.rs:296-313`）里
   `force=true` 的含义就是「允许改活动编辑场景」；而「怎么改才不会被编辑器下一次保存吃掉」在本 fork 里有唯一顺手的答案——
   `edited_scene_root()`（编辑器持续同步的那棵树）＋ `EditorInterface::mark_scene_as_unsaved()`。
   方案 ②会让这个工具在「整个工程一次改完」的主要用例上**永久残废**（活动场景几乎总是存在，且几乎总是调用方最想改的那一个），
   把一次调用变成「一半能写、一半请你自己换工具」的多步舞蹈——PLAYBOOK §6.10 把这种东西算缺陷。
2. **②并没有更安全**，只是把「静默丢失」换成「显式失败」；而活节点写入本身是**可验证**的：
   写后逐节点读回（`get_indexed`）＋ 与写入值比对，不一致就 **整体回退**（见 §4.3）。验证手段存在，就不该退化成拒绝。
3. 活动场景**不落盘**这条纪律仍然保留（编辑器持有同一场景时写文件 = lost update）；变的只是「不落盘的那份」从
   「刚刚加载出来的游离副本」变成「编辑器真正持有的活动树」。

D5 选了**「显式说明没有场景匹配」**而不是 `-32001`：`path_filter` 没匹配到任何场景是一个**合法的查询结果**
（`dry_run` 预览、批量脚本按目录扫零命中都很常见），换成错误会打断调用方正常的「先探测再决定」流程；
而 `total_scenes == 0` / `scenes_affected == []` 本身就是机器可判的字段，调用方想要硬失败可以自己判。

---

## 2. 根因复核（行号与验收方是否一致）

**验收方给的三处定位全部复核为真**（行号取本任务开工时的 HEAD `be62ea7ec9`）：

| 验收方说法 | 复核结果 |
|---|---|
| `:309-317` 对活动场景也用 `CACHE_MODE_IGNORE` 加载并 `instantiate()` 出游离副本 | **正确**。`:309` 是 `ResourceLoader::load(scene_path, "PackedScene", ResourceLoader::CACHE_MODE_IGNORE)`，`:317` 是 `packed->instantiate()`；该分支对**所有** `scene_files`（含 `is_active`）无条件执行，`:327/:332/:340` 的匹配与校验都作用在副本上 |
| `:451-455` 对 `live_open_scene` 跳过落盘、只调 `_mark_active_scene_unsaved()` | **正确**。`:451` `if (plan.mode == "live_open_scene")` → `:454` `_mark_active_scene_unsaved();`，副本随后在 `:524-526` 被 `memdelete` 丢弃 |
| `:81-86` 注释声称「with `force` it edits the live nodes」 | **正确**（原文在 `:84-85`），代码与其自身文档直接矛盾 |

**复核补充的两条（验收方未提，但决定修法）**：

1. 真正被编辑的从来不是「没人看的那份」这么简单：`plan.mode` 在 `:361` 就被定成 `"live_open_scene"`，
   而**提交阶段唯一的行为差异只有「跳不跳落盘」**——也就是说，发出「成功」的那一刻，工具自己也不知道它改的是哪棵树。
   所以修法必须把「写哪棵树」变成**计划阶段的事实**（`plan.instance`＋`plan.owns_instance`），而不是提交阶段的 `if`。
2. **`instance` 的所有权原来是无条件释放的**（`:387-389`、`:414-416`、`:434-436`、`:445-447`、`:486-489`、`:524-526` 六处
   `memdelete(planned[j].instance)`）。把活动场景的 `instance` 换成活节点树以后，这些 `memdelete` 会**把用户正在编辑的场景删掉**——
   这是修复方案①里唯一真正的坑，故新增 `_PlannedScene::owns_instance`（活动场景为 `false`）与唯一的释放入口
   `_release_planned_scenes()`（全部六处改调它）。

原实现确实会「报成功但没写」——红阶段实测（§5）里，**另一个工具读回的响应体 sha256 与调用前逐字节相同**
（`7ae14eaf…`，见 §5.1），随后 `editor_save_scene` 落盘的仍是旧值。

---

## 3. `scenes_affected[].mode` 语义表（一眼可判「写没写」）

实现里新增了两个布尔字段 `written` / `persisted`，与 `mode` 一起构成唯一的三行表（代码见 `project_cross_scene_write.cpp`
的计划阶段 `plan.mode = …`、提交后的 entry 组装、以及消息构造）：

| `mode` | `written` | `persisted` | 磁盘上有新值吗 | 活动场景？ | 语义（调用方视角） |
|---|---|---|---|---|---|
| `"dry_run"` | `false` | `false` | 否 | 否 | 预览：什么都没写；`message` 以 `Dry run: nothing was written` 开头 |
| `"offline_saved"` | `true` | `true` | **是**（原子发布，替换前先留原始字节） | 否 | 关闭的场景已真落盘，编辑器下一次保存也不会吃掉它 |
| `"live_open_scene_written"` | `true` | `false` | **否** | 是 | 活动场景的**活节点**已改、已逐节点读回验证、已 `mark_scene_as_unsaved()`；`message` 明说 `NOT on disk yet … call editor_save_scene` |

- **不存在「`written=true` 且其实没写」的组合**：`written=true` 只有两条产生路径——文件原子发布成功（`offline_saved`），
  或活节点写后每节点读回都与写入值一致（`live_open_scene_written`）；后者任何一步不一致都会**回退并整体报错**（§4.3）。
- 若强制要求「落盘才算写」的客户端，判据是 `persisted`；若只关心「内存里生效没有」，判据是 `written`。
- 三种 `mode` 互斥且穷尽；`mode` 词表在 `tools_list.renamed.json` 里**没有**任何声明（该契约只有 `name`/`description`/`inputSchema`），
  因此改名 `live_open_scene` → `live_open_scene_written` 不构成契约偏离；`offline_saved` / `dry_run` 两个旧 token 原样保留
  （TASK-018 证据脚本对 `offline_saved` 的断言因此仍然通过，§10.3）。

---

## 4. 逐工具表（本任务只改 1 个工具，无新增注册）

| `new_name` | 迁移源位置（**仅类别参考**） | 引擎依据（为什么这是自然形态） | 自然契约（本次变化部分） | C++ 落点 | 与迁移源的差异及理由 |
|---|---|---|---|---|---|
| `project_set_node_property_across_scenes` | `batch_commands.gd:257-369`（`cross_scene_set_property`）+ `372-391`（`_collect_scene_files`） | **`SceneTree::get_edited_scene_root()`**（编辑器持续同步的活树，`MCPTools::edited_scene_root()` 的封装，见 `tool_helpers.h:297-307`）＋ **`EditorInterface::mark_scene_as_unsaved()`**（`EditorNode` 自己用的「内存已改未存」标记）＋ **`Object::get_indexed/set_indexed`**（读回验证，TASK-028 G-1 同一套路径语法） | `scenes_affected[i]` 新增 `written`/`persisted`；活动场景 `mode` 改为 `live_open_scene_written`；`message` 分四种情形（预览 / 零命中 / 纯关闭 / 含活动）；`editor_rescan_triggered` 只在真的替换过文件时为 `true`；参数与 `inputSchema` **零改动** | `tools/project_cross_scene_write.cpp`（计划阶段活动场景分支、新增 `write_live_scene_property`、`_release_planned_scenes`、提交阶段两趟、消息构造）＋ `tools/project_cross_scene_write.h`（`class Node;` 前置声明、契约注释、新函数声明） | ①活动场景**不再**加载游离副本、**真的改活节点**（迁移源也是改活节点，但它用的是 `EditorInterface::get_edited_scene_root()`——本 fork 实测在 doctest 进程 SIGSEGV，故按引擎实际可用的 `SceneTree` 镜像来，见 PLAYBOOK §6.6 第 2 例）；②活节点写入有**读回验证 + 失败回退**（迁移源没有）；③零命中消息诚实（迁移源恒报成功文案）；④活动场景**排在所有文件之后提交**（迁移源无顺序保证）。 |

### 4.1 计划阶段：活动场景用活树，且所有权显式

- `is_active`（路径 == `edited_scene_root()->get_scene_file_path()`）时：`instance = edited_scene_root()`、
  `owns_instance = false`；**不加载文件**。
- 若两次读取之间编辑器已经换场景（`instance == nullptr` 或路径不再相等）→ 记入 `errors`，整调用按既有的
  all-or-nothing 语义拒绝（`-32000` + `data.scenes.errors`）；**绝不**退化成「悄悄去写文件」。
- 关闭场景照旧 `CACHE_MODE_IGNORE` + `instantiate()`，`owns_instance = true`。
- 匹配（`_collect_matching_nodes`）、逐节点校验（`prepare_node_property_value`）在两种情况下都作用在**将要被写的那棵树**上。

### 4.2 提交阶段：活节点排最后

- 第一趟：所有 `offline_saved` —— 改副本、`pack()`、`publish_file_atomically()`；失败时用**原始字节**回滚已发布的文件（既有语义不变）。
- 第二趟：`live_open_scene_written` —— 见 §4.3；成功才 `_mark_active_scene_unsaved()`。
- **为什么活节点必须最后**：它是唯一「不在磁盘上、无法用原始字节回滚」的目标。排在最后以后，「后面还会失败的步骤」不存在了，
  all-or-nothing 对两种目标同时成立；活节点自己失败时（§4.3）连已发布的文件也一并回滚（`data.rollback`）。

### 4.3 `write_live_scene_property()`：写活节点的四步，每步都有对应的撤销

1. **先校验**：`prepare_node_property_value()`（与文件半一模一样的规则）。
2. **先读旧值**：`read_node_property_path()`；若该路径当前**读不到**（`had_value == false`）→ 拒绝（`-32000` + `data.suggestion`），
   因为「无法撤销的写入」不许开始。
3. **写**：`apply_node_property_value()`（`set_indexed`，TASK-028 G-1 的同一表达式）。
4. **读回验证**：再 `read_node_property_path()`，与写入值比对（`_values_agree`：同类型用 `Variant::operator==`(= `hash_compare`)，
   `INT`/`FLOAT` 之间按数值比——`hash_compare` 对不同 `type` 恒 `false`，直接用会把 `1` 与 `1.0` 判成不一致）。
   不一致 → **本次调用已改过的每个节点按反序写回旧值**，写进 `data.live_nodes_restored`，整体报 `-32000`。

该函数声明在头文件里、不是 `static`，唯一原因是 **doctest 进程没有 `SceneTree`**（`edited_scene_root() == nullptr`），
只有「直接收节点列表」的入口才能在测试里断言这条读写回环（与 `prepare_node_property_value` 公开的原因相同）。

---

## 5. 红 → 绿证据（D1 与 D5）

### 5.1 现场脚本（真引擎、9888 编辑器端点）

- **红**：`mcp030_live_open_scene_write_evidence.ps1` 对**修复前**的构建（`--version = be62ea7ec`，HEAD）跑：
  `TASK-030 evidence: 22 checks, 7 failed`，退出码 **1**。关键三行（原始输出）：

  ```
  [FAIL] D1_open_scene_mode_says_written_not_persisted
         good entry={"count":1,"mode":"live_open_scene","nodes":["."],"scene":"res://scenes/good.tscn"}
  [FAIL] D1_another_tool_reads_new_live_value
         position={"x":1.0,"y":2.0}
  [FAIL] D1_open_scene_file_has_new_value_after_save
         good.tscn sha after save=cc7fc475…; contains Vector2(3, 4)=False contains Vector2(1, 2)=True
  [FAIL] D1_message_does_not_claim_open_scene_on_disk
         message=Applied: every closed scene was saved and the active open scene was edited in memory.
  [FAIL] D5_zero_match_message_says_no_match
         message=Applied: every closed scene was saved and the active open scene was edited in memory.
  ```

  **「什么都没发生」的字节级铁证**：红阶段「调用后另一个工具读回」与「调用前基线」两条响应体
  **sha256 完全相同**（同为 `7ae14eaf83edf585cdb1d1209b694c78415fbeb5a24c6c2cc955af74b6f58590`，各 166 字节）；
  而**同一次调用里关闭的** `side.tscn` 却真的落了 `Vector2(3, 4)`（该检查红阶段就 PASS）——
  证明缺陷不是「工具不会写」，而是「活动场景那一半是假的」。

- **绿**：同一脚本对修复后构建（`--version = be62ea7ec` == HEAD）跑：
  `TASK-030 evidence: 22 checks, 0 failed`，退出码 **0**（22/22 全 PASS；`port_9877` 前后 `pid=36392`）。

### 5.2 doctest（红/绿两阶段都跑了）

- **红**（先写测试、实现仍是 HEAD；新入口点尚不存在，故用 `#if 0` 临时屏蔽其用例，只跑行为级三段）：
  `--headless --test --test-case="*TASK-030*"` →
  `test cases: 1 | 0 passed | 1 failed`、`assertions: 29 | 22 passed | 7 failed`、`Status: FAILURE!`。
  失败点：`message.contains("No scene matched")`、`message.contains("Applied")`（应为 false）、
  `entry["written"]`、`entry["persisted"]`、`message.contains("in memory")`（应为 false）。
- **绿**（恢复实现与全部用例后）：`test cases: 1 | 1 passed`、`assertions: 38 | 38 passed | 0 failed`、`Status: SUCCESS!`。
- 红阶段所用的 `#if 0` **已完全移除**（见 §10.2 的 `test_mcp_server.h` sha256 与 git diff），
  最终提交的测试文件里没有屏蔽段。

---

## 6. 端到端链证据（真请求 / 真响应 / 真 sha256）

同一 scratch 工程：`res://scenes/good.tscn`（编辑器**打开且活动**，根节点 `Node2D position = Vector2(1, 2)`）
与 `res://scenes/side.tscn`（**关闭**，根节点同样 `Vector2(1, 2)`）。响应体一律 `curl.exe -s -o <file>` 落盘后算 sha256，
请求体由 `ConvertTo-Json` 生成、`--data-binary @file` 发送。

| 步 | 工具 / 参数 | 响应 sha256（字节） | 关键字段 |
|---|---|---|---|
| 1 | `editor_open_scene{path:"res://scenes/good.tscn"}` | `c10bcc07…` (126) | code 0 |
| 2 | `editor_get_node_properties{path:".", properties:["position"]}` | `7ae14eaf…` (166) | `{"x":1.0,"y":2.0}` |
| 3 | `project_set_node_property_across_scenes{type:"Node2D", property:"position", value:{x:3,y:4}, path_filter:"res://scenes", force:true}` | `8821b981…` (880) | 见下方正文 |
| 4 | 同上另一个工具读回 | `edd2622c…` (166) | `{"x":3.0,"y":4.0}` |
| 5 | `editor_save_scene{}` | `129c1c90…` (125) | `{"path":"res://scenes/good.tscn","saved":true}` |

第 3 步的完整正文（原样，未加工）：

```json
{"dry_run":false,"editor_rescan_triggered":true,"errors":[],"force":true,
 "message":"Applied: 1 closed scene(s) saved to disk, and the active open scene 'res://scenes/good.tscn' was edited in memory and marked unsaved (2 node(s) written in total). The closed scenes are on disk; the open scene is NOT on disk yet, so call editor_save_scene to persist it.",
 "path_filter":"res://scenes","property":"position",
 "scenes_affected":[
   {"count":1,"mode":"live_open_scene_written","nodes":["."],"persisted":false,"scene":"res://scenes/good.tscn","written":true},
   {"count":1,"mode":"offline_saved","nodes":["."],"persisted":true,"scene":"res://scenes/side.tscn","written":true}],
 "skipped_open_scenes":[],"total_nodes":2,"total_scenes":2,"type":"Node2D"}
```

三段链的落盘/读回事实（每一行都是脚本自跑的 check 原文）：

```
[PASS] D1_another_tool_reads_new_live_value
       position={"x":3.0,"y":4.0}
[PASS] D1_closed_scene_on_disk_has_new_value
       side.tscn sha before=fecebf4f… after=039f0b2d…; contains Vector2(3, 4)=True
[PASS] D1_open_scene_file_not_written_yet
       good.tscn sha before=0986e4a1… before save=0986e4a1…; contains Vector2(1, 2)=True
[PASS] D1_editor_save_scene_code0
       code=0 payload={"path":"res://scenes/good.tscn","saved":true}
[PASS] D1_open_scene_file_has_new_value_after_save
       good.tscn sha after save=9e9ddfdd…; contains Vector2(3, 4)=True contains Vector2(1, 2)=False
```

**混合场景（活动 + 关闭）关闭者仍真落盘**：第 3 步里 `side.tscn` 的 `mode=offline_saved / written=true / persisted=true`，
其文件 sha256 由 `fecebf4f…` 变为 `039f0b2d…`，文件正文含 `Vector2(3, 4)`（`D1_closed_scene_on_disk_has_new_value`）。
另有一条独立回归：对同一目录再发一次全关闭属性的提交（`D1_closed_only_commit`，880 字节响应 `acd5a487…`），
`side.tscn` 落盘出现 `rotation = 0.75`（`regression_closed_scene_rotation_on_disk` PASS）。

**读回值≠请求值的对照**：第 2 步与第 4 步的**响应 sha256 不同**（`7ae14eaf…` vs `edd2622c…`），
说明「活动场景真的变了」；红阶段这两步**相同**（§5.1）。

---

## 7. D5 前后对照（零命中也宣称「已应用」）

`path_filter="res://scenes/side.tscn"`（**文件**而不是目录）→ 零命中。

| | 修复前（红，HEAD 构建） | 修复后（绿，本提交） |
|---|---|---|
| `total_scenes` / `scenes_affected` | `0` / `[]` | `0` / `[]`（不变） |
| `message` | `Applied: every closed scene was saved and the active open scene was edited in memory.` | `No scene matched 'res://scenes/side.tscn': nothing was written. 'path_filter' names a directory that contains .tscn files, not a single scene file; check it and call again.` |
| `message` 含 `Applied` | **是**（缺陷） | **否** |
| 响应 sha256（字节） | `4e96fe59…` (433) | `994054ac…` (520) |
| 两个 `.tscn` 的 sha256 | 未变（`D5_zero_match_wrote_nothing` 红阶段即 PASS） | 未变（同一检查绿阶段 PASS） |
| `dry_run` 分支同族措辞 | `Dry run: nothing was written. Call again with force=true…`（**零命中时也是这句**） | 零命中 → `Dry run: no scene matched '…'`；有命中 → `Dry run: nothing was written. N scene(s) / M node(s) would be written; …` |

---

## 8. 门（全部自跑，贴真实输出与退出码）

| 门 | 命令 | 结果 |
|---|---|---|
| ⓪ 构建绑定 | `modules\mcp_server\scripts\build_local.cmd -Force`；`--version` vs `git rev-parse --short HEAD` | 退出码 **0**；`4.8.dev.custom_build.be62ea7ec` == `be62ea7ec9` |
| ① 契约子集逐字 | `scripts\check_contract_subset.ps1 -Group project_cross_scene_write` | 退出码 **0**；`3/3 checks passed`；`[PASS] editor_9888_contract_subset` 与 `[PASS] game_9889_contract_subset` 各含 `project_set_node_property_across_scenes: name=True description=True inputSchema=True`；`implemented_union=91 tools (editor endpoint) / 53 tools (game endpoint)`；`[PASS] guard_user_port_9877 pid_before=36392 pid_after=36392` |
| ② 三类证据 + 端到端链 | `curl.exe -s -o <file> --data-binary @file` 打 9888 | 见 §6 与 §9；端到端链 22/22 全 PASS |
| ③ 模块 doctest | `--headless --test --test-case=[MCPServer]*`（工作目录 = 仓库根） | 退出码 **0**；`test cases: 220 | 220 passed | 0 failed | 1429 skipped`；`assertions: 8481 | 8481 passed | 0 failed`；`Status: SUCCESS!`（基线 219/8443 → **+1 用例、+38 断言**） |
| ④ 全引擎回归 | `--headless --test` | 退出码 **0**；`test cases: 1646 | 1646 passed | 0 failed | 3 skipped`；`assertions: 432763 | 432763 passed | 0 failed`；`Status: SUCCESS!`（基线 1645/432725 → +1 / +38） |
| ⑤ 批次收口 | `scripts\accept_m1.ps1` 连跑两次 | 两次都 `22/22 cases passed`，两次 `PASS` 行 **逐条一致**（`identical=True`，各 22 条，`FAIL` 0 条）；两次都打印 `implemented tools = 91 (editor endpoint) / 53 (game endpoint); contract = 171; known_deviation = per-batch verbatim gate only` |
| ⑥ 收窄点清单 | `python scripts\check_narrowing_points.py` | 退出码 **0**；`scanned=30 pinned=30`；`PASS: every narrowing point of the module is annotated and pinned`。本任务未新增任何 `(real_t)`/`(float)`/`Color(`/`Vector2(`/`Vector3(`/`Vector4(` 收窄点（新增的比对只用了 `(double)`） |

**重跑既有证据脚本（确认未回退）**：

| 脚本 | 结果 |
|---|---|
| `mcp028_subpaths_clear_import_evidence.ps1` | 退出码 **0**；`TASK-028 evidence: 27 checks, 0 failed` |
| `mcp029_clear_default_evidence.ps1` | 退出码 **0**；`TASK-029 evidence: 20 checks, 0 failed` |
| `mcp018_b3_closure_evidence.ps1`（本工具所属组的端到端脚本） | 退出码 **1**；`104 checks, 1 failed` —— 唯一失败是 **`derivation_new_union_is_old_plus_exactly_ten`（old=96 new=113）**，见 §10.3 的「与本次改动无关」判定；**所有 `across_scenes_*` 检查全 PASS**（dry_run 零写入、坏中间文件 `-32000` 整体拒绝且两个文件 sha256 不变、值闸门 `-32000` errors=2、提交落盘 `offline_saved` + 文件正文含 `rotation = 0.75`） |

端口与进程纪律（每次开跑前后观测）：全程**只有用户自己的** `9877 / PID 36392`（mono 4.7.1，从未占用、杀或重启）；
测试端口 `9888/9889` 在每次脚本开始时 `owner=-1`、结束时已释放；收尾时 `Get-Process godot*` 仅剩 `36392` 一条，
`netstat` 中 9877 之外无本模块留下的 LISTENING。

---

## 9. 三类证据（成功 / 缺参 / 底层失败）

| 类别 | 证据 |
|---|---|
| 成功 | §6 第 3 步（混合活动+关闭，`code 0`，`live_open_scene_written` + `offline_saved`）；`mcp018` 的 `across_scenes_commit`（全关闭，`Applied: 2 closed scene(s) saved to disk (3 node(s) written)`，文件正文含 `rotation = 0.75`） |
| 缺参 → `-32602` | 保持既有语义：缺 `value` → `-32602 Missing required parameter 'value'`；`dry_run: "nope"` → `-32602`。由 TASK-018 doctest 第 (8) 段在本次构建上覆盖并 PASS（`mcp030` 脚本不重复构造） |
| 底层失败 → `-32000` / `-32001` | `mcp018` 实跑：故意损坏的 `two.tscn` → `-32000 "Refusing to write: 1 scene(s) of 'res://cross' cannot take this call"`，`data.scenes.scenes_named=["res://cross/two.tscn"]`、`reason="not a loadable PackedScene"`，两个 `.tscn` sha256 **前后完全相同**；`value=1e20` → `-32000` 且 `errors=2`、零写入 |
| 不可构造的类别 | **活节点写后读回不一致**在真实编辑器里不可从线上构造（编辑器把属性写进去就一定会读回来；能让 `set` 成功而读回不同的属性在本工程里没有已知实例）。该分支用 doctest 直接构造（§5.2 的 (4b)：第二个节点不声明该属性 → 整调用失败且**第一个节点被写回旧值** `Vector2(5,6)`，`data.live_nodes_restored=["Root"]`），并在此显式声明"线上不可构造" |
| 跨工具活证据链 | §6（写活动场景 → **另一个工具**读回新值 → `editor_save_scene` → 文件里含新值；同一次调用里关闭的场景仍真落盘） |

---

## 10. 文件 sha256 与改动面

### 10.1 受控文件（本次改动）

```
9a2a93a3cce8bb26440651255fd7b6a661462bca968a195e0fb4e9026094cd6c  modules/mcp_server/tools/project_cross_scene_write.cpp
a1d2e1b161f7dbfb279b88d7cdce7d8483ed20c7c5168bee7106ba968065af62  modules/mcp_server/tools/project_cross_scene_write.h
22267a18422c6433d5d2603c395b22f71aa23def846c96a1bf184557f689d981  modules/mcp_server/tests/test_mcp_server.h
a985f296cf2495bac7dc70645b80180219357396d297001c38d9e4e4981fe0b8  modules/mcp_server/scripts/mcp030_live_open_scene_write_evidence.ps1
```

- `project_cross_scene_write.cpp`：`git diff --stat` 内 **453 行变更**（含注释）；`project_cross_scene_write.h` 63 行；
  `test_mcp_server.h` +105 行（**只新增一个 `TEST_CASE`**，未改动既有用例）。
- 证据脚本 **0 个非 ASCII 字节**（`non_ascii_bytes=0`，19054 字节），满足「`.ps1` 一律纯 ASCII」纪律。
- **没有**改动契约/映射/生成器：`tools_list.renamed.json`、`tool-rename-map.json`、`tool-groups*.json`、
  `gen_renamed_contract.py` 全部未动；工具注册数不变（91/53），`inputSchema` 与 `description` 逐字未变（门① 证明）。

### 10.2 工作树

`git status --porcelain` 只剩既有未跟踪物（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`）
与本报告自身；无 `docs/spec/**`、无 `DECISIONS.md`（决策日志在 hof-rs，本 fork 只读）。**未 push**。

### 10.3 一项必须显式声明的既有失败（不是本次引入）

`mcp018_b3_closure_evidence.ps1` 的 `derivation_new_union_is_old_plus_exactly_ten` 失败：

- 该检查把**冻结的旧 addon 脚本**里的 96 个字面工具名，与**五个 manifest 里 `implemented=true` 组的并集**（现为 113）比较，
  断言「并集 == 旧集合 + 恰好 10 个」；`removed=[]`、`added_diff=[]`，即**没有任何工具被移除**，
  多出来的 17 个是 TASK-019…TASK-029 累计新增的工具（TASK-018 当时并集 106，恰好 +10，故当时 PASS——见 `docs/reports/REPORT-018-b3-closure.md:158`）。
- **与 TASK-030 无关**：该断言的两个输入（manifest 文件、冻结的旧脚本）本次**一字未改**（§10.1 证明改动面只有 3 个文件 + 1 个新脚本），
  且它**不读**线上 `tools/list`、不读本工具代码。旁证：TASK-030 之前发布的 `REPORT-AUDIT-M4d`（§F 门① 行）
  记录的并集就是 `91 / 53`，与本次门① 打印的完全相同。
- **处置建议**：交给决策者——这条断言属于 TASK-018 的历史不变式，应当在某个后续任务里改成「并集 ⊇ 旧集合 且 removed == []」
  （或直接冻结成 manifest 快照），但**本任务书禁止改契约/生成器与其它脚本文档**，故只在此报缺陷，不在本批修改。

---

## 11. deviations / blockers / next_step_recommendation

### deviations（逐条显式）

1. **D5 选了「显式说明无匹配」而非 `-32001`**：理由见 §1；`total_scenes == 0` 已是机器可判字段。
2. **`mode` 词表变化**：活动场景 `live_open_scene` → `live_open_scene_written`，并新增 `written` / `persisted` 两个布尔。
   响应形状不在契约文件里（契约只有 `name`/`description`/`inputSchema`），门① 逐字通过证明契约面零偏离；
   `offline_saved` / `dry_run` 未改名，TASK-018 证据脚本对 `offline_saved` 的断言仍 PASS。
3. **`editor_rescan_triggered` 语义收窄**：过去「有任何 `scenes_affected`」即为 `true`，现在只在**真的替换过文件**（`disk_scenes > 0`）时为 `true`。
   理由：活节点编辑不触碰资源文件系统，无谓的 `EditorFileSystem::scan()` 是纯开销；该字段不是契约字段。
4. **新增公开函数** `MCPTools::write_live_scene_property()`（头文件声明）：doctest 进程无 `SceneTree`，
   只能通过「直接收节点列表」的入口断言活节点写入及其读回/回退；与 `prepare_node_property_value` 公开的理由相同。
5. **doctest 红阶段的技术处理**：新入口点在旧实现里不存在，会让整个测试 TU 编译失败。
   因此红阶段用 `#if 0` 临时屏蔽第 (4) 段（只在**本机临时树**，**未提交**），先把 (1)(2)(3) 段跑成红；
   恢复实现后解除屏蔽，最终提交的测试文件里**没有** `#if 0`/`#endif`（见 §10.1 的 sha256）。
   第 (4) 段本身因此没有「先红」的执行记录，如实声明。
6. **报告未把 mcp018 判为「全绿」**：如实记为 `104 checks, 1 failed`，并给出「与本次无关」的判定依据（§10.3），而不是删掉这条失败。
7. 过程失误（如实记录，不影响产物）：本次曾用一条错误的 `Copy-Item` 路径做实现文件的临时备份，导致 `project_cross_scene_write.h` 的
   编辑在一次 `git checkout --` 中丢失并从已提交内容重新施加；`project_cross_scene_write.cpp` 的备份完整，最终内容以 §10.1 的 sha256 为准。

### blockers

- 无。

### next_step_recommendation

1. **给独立验收方的两条建议**：(a) 复跑 `mcp030_live_open_scene_write_evidence.ps1`（9888/9889，22/22 应全 PASS，退出码 0），
   并对照红阶段日志（7 failed）确认「另一个工具读回」的响应 sha256 真的发生了变化；
   (b) 门③/④数字应为 220/8481 与 1646/432763，**0 failed**。
2. **本任务未覆盖、建议下一个任务处理的 M4d 缺陷**（超出 TASK-030 范围）：D2（门⑥ 六种拼写可被绕过）、
   D3（`editor_get_node_properties` 全量列举混入检查器分组标签，且 `Material`/`material` 大小写冲突让不区分大小写的客户端无法解析）、
   D4（未知参数名被静默忽略）、D6（游戏侧 `node_path` 形态描述不一致）。
3. **`mcp018` 的历史不变式**（§10.3）建议单独起一个小任务收口（改断言或冻结快照），否则该脚本会持续红。
4. **可选加固**：为 `project_set_node_property_across_scenes` 增加「只有活动场景命中」（`disk_scenes == 0`）的线上用例，
   与「只有关闭场景命中」的用例；本次已覆盖「活动 + 关闭混合」与「全关闭」两端。

---

## 12. 收尾：报告提交后的重建与复验

§8 的门①–⑥ 全部跑在 `HEAD = be62ea7ec9`、`--version = 4.8.dev.custom_build.be62ea7ec` 的构建上（即任务开工时的 HEAD）。
本报告（`e7d0d218f1`）与证据脚本（`b6203ba2b7`）的提交只动 `modules/mcp_server/docs/**` 与 `modules/mcp_server/scripts/**`，
不改变任何被编译的源码；为了让工作树的二进制与最终 HEAD 一致（PLAYBOOK R-1 的纪律），报告提交后**又用
`scripts/build_local.cmd -Force` 重建了一次**并复验：

- `--version` = `4.8.dev.custom_build.e7d0d218f` == `git rev-parse --short HEAD`（`e7d0d218f1`）；
- `--headless --test --test-case="*TASK-030*"` → `1 passed / 0 failed`、`assertions 38/38`、`Status: SUCCESS!`；
- `mcp030_live_open_scene_write_evidence.ps1` 复跑 → `22 checks, 0 failed`，退出码 **0**（`0` 条 FAIL 行）。

因此最终交付状态是「**二进制 == HEAD，且本任务的端到端链与 doctest 在最终二进制上仍全绿**」。
