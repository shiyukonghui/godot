# TASK-033 — B5 批次 1：**动画族 14 工具** + 三条小收口

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册），再读本文件。
> **本批起，设计一律「引擎优先」**（`DESIGN-DETAIL` **§21 / GDR-23**）：迁移源只回答「有哪些类别的工具、大致干什么」；
> **「怎么用才顺手」以引擎源码为第一参考源**（`core/**`、`scene/**`、`editor/**`）。
> 报告写到 `docs/reports/REPORT-033-b5-animation.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 三条小收口（先做，都是 M4e 复核的遗留）

1. **D-M4e-1（medium）**：门⑥ 的声明边界**未覆盖** 5 种同类拼写，且**未打印**：
   `float x = -1.0e300;`、`float x = (1.0e300);`、`float x = 0x1p1000f;`、`typedef` 别名声明、
   `float arr[1] = { 1.0e300 };`。
   → **二选一**：并入 `PATTERNS`（**并为每种加「插入即 exit 1」探针**），或至少写进 `NOT_COVERED` 的**打印文本**。
   （当前 `tools/**` 无此类拼写，故这是**覆盖缺口**而非线上缺陷。）
2. **D-M4e-2（low）**：`running_game_get_node_properties` 的描述写「不传则返回**所有**属性」，
   而实现只答 `PROPERTY_USAGE_EDITOR|SCRIPT_VARIABLE` 子集（Node2D 上 27/42），编辑器同族答 42。
   → 让**描述与实现一致**（改描述走 **`DESCRIPTION_OVERRIDES`** + 重生成 + 更新指纹），或让**实现与描述一致**
   （**按引擎语义判断哪个才是对的**，说明理由）。**注意**：两者只能选一个，且必须说明为什么另一个不是正确答案。
3. **D-M4e-3（low）**：`project_set_node_property_across_scenes` 在「`path_filter` 是**单个场景文件**、
   文件匹配但**该类型节点数为 0**」时，消息里后半句建议（"names a directory that contains .tscn files, not a single scene file"）
   **不成立**。→ 修正措辞（建议只在**真的**指向文件时出现）。

## 1. B5 批次 1：动画族 14 个工具（**以 `docs/tool-groups-b5.json` 为准**）

| 组 | 数量 | 工具 |
|---|---|---|
| `editor_animation_write` | 4 | `editor_add_animation_track`、`editor_create_animation`、`editor_remove_animation`、`editor_set_animation_keyframe` |
| `editor_animation_tree_write` | 7 | `editor_create_animation_tree`、`editor_add_state_machine_state`、`editor_add_state_machine_transition`、`editor_remove_state_machine_state`、`editor_remove_state_machine_transition`、`editor_set_blend_tree_node`、`editor_set_animation_tree_parameter` |
| `editor_animation_read` | 3 | `editor_get_animation_info`、`editor_get_animation_tree_structure`、`editor_list_animations` |

**要求**：
1. **引擎优先设计**：每个工具先读引擎源码（`scene/animation/**`、`scene/resources/animation.h` 等），
   回答「引擎里对应什么 API、**一次调用能做到什么**」，再决定参数形态与返回字段；
   **报告中每个工具必须有「引擎依据」列（API + 文件:行）**。
2. **顺手性自评**：给出**至少一条跨 ≥4 工具的零字符串手术链**（例如
   建动画 → 加轨 → 加关键帧 → 读回 → 建 `AnimationTree` → 加状态/过渡 → 读结构 → 设参数 → 读参数），
   并**逐步标出调用方字符串处理次数（目标 0）**；
   返回值必须**可直接喂回**（例如读回的轨/状态/节点标识能原样作为删改工具的输入）。
3. **三类证据**（成功 / 缺参 `-32602` / 底层失败）+ **每组一条跨工具活证据链**。
4. **不得假成功**：删改类工具在目标不存在时必须 `-32001` + `data.suggestion`；
   `remove_*` 类必须给出**真实删除计数**；创建类必须**读回**核实（例如动画真的进了 `AnimationPlayer`）。
5. **门⑥ 三段式**：本批若引入任何收窄点，必须**逐条**列出「新增点 × 经过的闸门 × 证据」（§22.3b 规则 4）。
6. `docs/tool-groups-b5.json` 里这三组置 `implemented=true`（**只改这几个布尔**）。
7. **`scope` 纪律**：全部 `editor_*` → **必须缺席于游戏端点 9889**、在游戏进程调用 `-32601` 不执行。

## 2. **跨任务结论的有效性纪律（D86，本批起强制）**

**任何从别的报告/任务书里引用来的结论，必须**：
① 标明它**测自哪个提交**；② **在参考它开工之前复测一次**；③ 若发现它已过期，**在报告里显式指出并 append-only 勘误**。
（背景：`REPORT-032` 的「写侧缺口仍未修」是从 `REPORT-024b` 照抄的陈旧结论，M4e 复核证明其为假 —— 差点造成一批无用功。）

## 3. 门

- 第 0 步：`scripts/build_local.cmd -Force`（`tests=yes`）重建 + 校验 `--version` == HEAD
  （**从 cmd 启动**：Git Bash 的 `MSYSTEM` 会让 SCons 提前 255 退出）。
- 五道门（**门①按三组各跑一次**）+ **门⑥ 三段式**（`check_narrowing_points.py` + `--coverage` + 探针脚本）。
- 回归：重跑 `mcp030`/`mcp031`/`mcp032` 证据脚本确认未回退。

## 4. 报告

按手册 §4（含「引擎依据」列），写到 `docs/reports/REPORT-033-b5-animation.md`；另加：
「三条小收口的前后对照」「14 个工具 × 引擎依据 × 自然契约 × 与迁移源差异及理由」
「零字符串手术链（含字符串处理次数）」「B5 进度（14/58）」。**返回值：≤15 行总结 + 报告路径。**