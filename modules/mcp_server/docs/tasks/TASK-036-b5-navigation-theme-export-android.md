# TASK-036 — B5 批次 4（收官）：navigation / theme / export / android 共 14 工具

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册），再读本文件。
> 引擎优先（§21/GDR-23）、顺手性（§23/GDR-25）、门⑥（§22.3/§22.3b）是本批规范依据。
> 报告写到 `docs/reports/REPORT-036-b5-navigation-theme-export-android.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 两项小收口（决策者裁决）

1. **`docs/tool-groups-b5.json` 里 `editor_set_physics_layers` 的注记与 schema/映射不一致**
   （注记声称写 `ProjectSettings` 的工程层名，而 schema 与 rename-map 是**节点作用域**）→
   **修正注记**（只改注记文本，不改 schema/映射），并在报告里给出前后对照。
2. **两个「枚举/索引声明成字符串」候选的裁决**（TASK-035 上报，决策者已裁）：
   - `editor_set_shader_material.material_slot`：**保持 `string`** —— 它**主要是槽位名**（引擎里材质槽就是属性名），
     同时接受十进制索引是**便利**而非类型错误；
   - `editor_simulate_key.keycode`：**保持 `string`** —— 引擎侧它是**枚举名**（`KEY_A` 之类），
     让智能体写名字比写魔法整数**更顺手**（GDR-23）。
   → 报告里**各给一句理由**并**实测**「名字写法可用」，**不改契约**。

## 1. B5 批次 4：14 个工具（**以 `docs/tool-groups-b5.json` 为准**）

| 组 | 数量 | 工具 |
|---|---|---|
| `editor_navigation_write` | 2 | **`editor_bake_navigation_mesh`（`fix_implementation_first`）**、`editor_set_navigation_layers` |
| `editor_navigation_read` | 1 | `editor_get_navigation_info` |
| `running_game_navigation_write` | 1 | `running_game_move_player_to_target` |
| `project_theme_write` | 5 | `project_create_theme`、`project_set_theme_color`、`project_set_theme_constant`、`project_set_theme_font_size`、`project_set_theme_stylebox` |
| `project_theme_read` | 1 | `project_get_theme_info` |
| `project_export_read` | 2 | `project_get_export_info`、`project_list_export_presets` |
| `project_android_read` | 1 | `project_get_android_preset_info` |
| `os_android_read` | 1 | `os_list_android_devices` |
| `os_android_write` | 1 | `os_deploy_to_android_device` |

## 2. **第 3 个 `fix_implementation_first`：`editor_bake_navigation_mesh`**

迁移源**没有真正烘焙**（或烘焙结果不可用/未回读核实）却可能报成功。
→ **先写红测试**证明「调用后导航数据没有真的生成/没变化」，再按引擎语义实现
（`NavigationRegion3D::bake_navigation_mesh` 是**异步**的：要处理 `bake_finished` 信号/轮询状态），
**必须走 GDR-20 延迟通道**，并用**另一工具**（`editor_get_navigation_info` 或读回网格数据）证明**真的产出了**。
**不得**因为「异步难等」就退化成假成功；若某环境下**无法**烘焙（无导航服务器等），
必须**能力感知的诚实拒绝**（`-32000` + `data.suggestion`）。

## 3. **Android / export 组：预授权的诚实边界**

`project_export_read` / `project_android_read` / `os_android_read` / `os_android_write` 需要**Android 导出环境/设备**。
**决策者预授权**：若本机**没有** SDK/设备/导出预设，则：
1. **仍要实现工具**，但要把「**能力缺失**」检测出来，返回**诚实拒绝**（`-32000` + `data.suggestion`：缺什么、怎么装）；
2. **不得**伪造成功、不得回显假数据（例如列出并不存在的设备）；
3. 「**能力缺失**」本身就是**有效证据**（要给出「本机确实没有」的实测依据：SDK 路径不存在 / `adb devices` 为空等）；
4. 若本机**确有**可用预设/设备，则给出**真实的成功路径**证据。
5. 报告里明确列出：**哪些分支只拿到了「能力缺失」证据、哪些拿到了真实成功证据**（不得混为一谈）。

## 4. 通用要求

1. 每工具一行「引擎依据」（API + 文件:行）；与迁移源差异给理由。
2. **≥1 条跨 ≥4 工具的零字符串手术链**（逐步字符串处理 0 次）。
3. 三类证据 + 每组一条跨工具活证据链。
4. 不得假成功；`project_theme_*` 的写必须**回读核实**（主题项的写入很容易被引擎归一化/夹取 → 按 §20.6 用 `ignored` 语义）。
5. `running_game_move_player_to_target`：**不能**只是 `position = target` 的瞬移——
   按引擎语义（导航代理/寻路）实现，并给出「真的沿路径移动」的可观察证据（位置随帧变化）；
   若引擎能力不足，如实说明并给出最诚实的形态（**不得**假装寻路）。
6. 带整数 default 的新工具套用既有归一化办法。
7. `docs/tool-groups-b5.json` 里这 9 组置 `implemented=true`（只改布尔）→ **B5 = 58/58 收口**，报告给出机器校验输出。
8. **门⑥ 三段式** + §22.3b 规则 4；`editor_*` 缺席于 9889，`running_game_*` 缺席于 9888。
9. **D86 结论有效性纪律**。

## 5. 门

- 第 0 步：`scripts/build_local.cmd -Force`（`tests=yes`）重建 + 校验 `--version` == HEAD（**从 cmd 启动**）。
- 五道门（**门①按 9 组各跑一次**）+ 门⑥ 三段式。
- 回归：重跑 `mcp035`/`mcp034`/`mcp033`/`mcp032`/`mcp030`。
- **B5 收口校验**：`check_tool_groups.py --batch B5` + `--check-completeness`（应 exit 0，且 171 全部 implemented）。

## 6. 报告

按手册 §4（含「引擎依据」列），写到 `docs/reports/REPORT-036-b5-navigation-theme-export-android.md`；另加：
「`bake_navigation_mesh` 红→修全程与异步处理」「Android/export 的**能力证据 vs 真实成功**分列」
「两项小收口前后对照」「零字符串手术链」「**B5 = 58/58 与 171/171 收口**的机器校验输出」。
**返回值：≤15 行总结 + 报告路径。**