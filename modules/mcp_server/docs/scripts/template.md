# TOOL-NAMING — Godot MCP 工具命名规范与 174 项对照表（171 个注册工具）

> **文档性质**：规范性（normative）。本文件是工具命名的**唯一表述来源**；机器可读的**唯一事实源**是同目录的
> [`tool-rename-map.json`](./tool-rename-map.json)（`@@MAPBYTES@@` 字节，sha256 `@@MAPSHA@@`，174 条 → **171 个注册工具**）。
> 本文第 2 节的完整对照表由脚本**从该 JSON 生成**，不是手工转录；脚本与断言输出见
> `modules/mcp_server/docs/scripts/gen_table.py`（本仓内，可复跑）。
>
> **决策依据**：hof-rs `DECISIONS.md` 的 **D34**（命名审计：三类可复现事故源 + 最高严重度的安全发现）、
> **D38**（用户裁决：一次做全 + 通道前缀 + 因此重做授权判定）、**D41**（174 项映射产出 + 授权判定口径纠正 + 四项开放项判定）、
> **D45**（采纳独立审计的 D-1..D-8：两个截图工具改条件写、**取消两对有损合并**、`disposition` 枚举化 + `merge_target`、
> 三处引文失真修正；工具总数 174 − 2 下架 − 1 无损合并 = **171**）。
> 引擎侧配套条款见 `DESIGN-DETAIL.md` §16（引擎优先执行顺序）、**GDR-16**/**GDR-17**/**GDR-18**、
> §14（GDR-12..GDR-15：HTTP 四项收紧、fixture 重采、错误码、合入措辞）与 §10（工具移植批次 B1–B5，GDR-9）。
>
> **本文不做的事**：不重新推导 174 项语义（已冻结在 JSON）；不改任何代码；不改变任何工具的实现行为。

---

## 1. 命名规范

### 1.1 通道前缀（channel）——名字的第一段即作用域自证

形态：**`<channel>_<verb>_<object>[_<qualifier>]`**，即**先通道后动词**。第一段永远只有一个职责：
回答「这个工具**作用在哪个进程/介质上**」，不看文档也能判定。

| 通道前缀 | 定义与判据（取自 JSON `convention.channel_prefixes`） | 工具数 |
|---|---|---|
| `editor_` | 编辑器进程 / 编辑场景 / **编辑器进程内的全局单例**（`Input`、`InputMap`、`AudioServer`、`Performance`、`EditorInterface` 等） | @@CNT:editor@@ |
| `running_game_` | **运行中的游戏进程**（经 `user://` 文件 IPC 或独立进程端口到达游戏侧） | @@CNT:running_game@@ |
| `project_` | **项目磁盘**（文件内容、资源、`.tscn`/`.tres`、`ProjectSettings`、导出预设、脚本与着色器文件） | @@CNT:project@@ |
| `os_` | **外部进程 / 设备**（`adb` 等本机可执行程序与外接设备） | @@CNT:os@@ |

判据的三条关键推论（全部有 JSON `reason` 支撑）：

1. **「谁的状态被改」优先于「谁发起了调用」**。`play_scene` 启动的虽然是游戏，但动作发生在
   **编辑器的播放控制**上（`EditorInterface.play_*`），故 `editor_play_scene`，**不是** `running_game_*`。
   反之 `get_game_screenshot` 读的是游戏侧经 `user://mcp_screenshot.png` 文件 IPC 落下的截图，
   故 `running_game_capture_screenshot`。
2. **单例归属决定通道**。`simulate_*`(5) 与 `get_input_actions`/`set_input_action` 注入的是
   **编辑器进程**的 `Input`/`InputMap` 单例，**根本到不了游戏**——这正是 D27 E3 根因的复现。
   因此它们全部是 `editor_`，而不是任何「游戏输入」语义的名字。
3. **`project_` 与 `editor_` 的边界判据 = 是否作用于编辑器实时状态**（D41 开放项 1）：
   `save_scene`→`editor_`；`create_scene`/`delete_scene`/`get_scene_file_content`/`cross_scene_set_property`→`project_`；
   `analyze_scene_complexity` 主契约是磁盘路径（**仅在 `path` 为空时**回退当前编辑场景）→`project_`。
   同理由 `get_android_preset_info` 解析的是 `res://export_presets.cfg`，介质是项目磁盘，
   故是 `project_get_android_preset_info`，**不是** `os_*`。

### 1.2 动词闭集与每个动词的唯一含义

动词**只能**取自下表 @@VERBCOUNT@@ 个（源自 JSON `convention.verb_closed_set`）。每个动词只允许有**一个**含义；
同一动作**不得**用两个动词表达。表中「用对了」的例子全部是真实新名（可在第 2 节逐行核对）。

@@VERBDEFS@@
**最容易选错的三对动词**（用一句判据解决，实现者按此选词）：

| 该选谁 | 判据 |
|---|---|
| `get_` vs `list_` vs `read_` | 返回值是**一个对象的状态** → `get_`；是**一个集合的元素清单** → `list_`；是**文件/资源的内容本身** → `read_` |
| `find_` vs `search_` | 在**已知容器**里按条件**定位对象** → `find_`；在**一批文件**里按模式找**命中**（哪些文件/哪些行） → `search_` |
| `create_` vs `add_` · `remove_` vs `delete_` | 实体**此前不存在** → `create_` / 从容器**摘掉成员**但实体仍在 → `remove_`；实体**已存在**、只是挂进容器 → `add_` / **实体本身被销毁** → `delete_` |

### 1.3 禁止项

| 禁止 | 为什么 | 反例（旧名 → 应有的新名） |
|---|---|---|
| **`update_`** | 它不是闭集动词；「更新」既可指改单属性、也可指改文件，语义不可判定。单属性一律 `set_`；**磁盘文件整篇读改写**才用 `edit_`。 | `update_property` → `editor_set_node_property`；`set_blob` 类改文件内容 → `project_edit_*` |
| **名词前缀**（如 `tilemap_*`、`timer_*`） | 第一段必须留给通道，第二段必须留给动词；名词开头会挤掉通道位，使作用域不可见。 | `tilemap_set_cell` → `editor_set_tilemap_cell`（对象里才出现 tilemap） |
| **`game` / `runtime` 出现在非通道位** | 它们是通道语义的同义词，出现在对象位会造成「通道已声明两次且可能互相矛盾」。通道只有一个合法写法：`running_game_`。 | `get_game_scene_tree` → `running_game_get_scene_tree`（无 `game_` 残片） |
| **同一动作两种动词** | 会让「按动词段生成策略名单」失效，也让智能体无法靠动词推断读写。 | 选中/反选中本可 `select_`/`clear_`，闭集内统一为 `set_`/`remove_`：`select_nodes`→`editor_set_node_selection`、`clear_editor_selection`→`editor_remove_node_selection` |

### 1.4 长度判据：**不设软上限**

D38 用户裁决：**名字可以更长更直观**——智能体调错一次工具浪费的 token 远超过名字本身的 token。
因此本规范**不设字符数上限**，唯一判据是：

> **不看文档、只看名字，即可确定「作用进程/介质 + 动作 + 对象」。**

**三个「长而好」的例子**（越长的部分全都在消歧）：

| 新名 | 长在哪里、长了有什么用 |
|---|---|
| `running_game_move_player_to_target_via_navigation` | 25 字符的 object 把「移动谁 / 移到哪 / 怎么到（寻路而非直移）」全部写死；它会擦除与 `running_game_move_player_to_target` 的歧义——两个工具都叫 `move_`，靠 object 区分。 |
| `project_set_node_property_across_scenes` | 一眼看出介质是**磁盘多场景**（`project_`）而非当前编辑场景（`editor_`），且是 `set_` 单属性写；旧名 `cross_scene_set_property` 把 `cross_scene` 放在动词前，通道与动作都不可判定。 |
| `editor_set_tilemap_cells_in_rect` | 通道（编辑器编辑场景）+ 动词（`set_`=写）+ 对象（矩形区域内的一组瓦片）+ 限定（`in_rect`）四段齐全；旧的 `tilemap_fill_rect` 用 `fill` 这个闭集外动词，且以名词开头。 |

**两个「短而坏」的反例**：

| 短名 | 坏在哪 |
|---|---|
| `move_to` | 4 段里没有通道、没有介质、没说是「谁」移动（角色？节点？），`move` 的对象完全缺失；新名 `running_game_move_player_to_target` 补了通道与对象。 |
| `clear_output` | 短且歧义：清空的是编辑器 Output 面板？日志文件？还是运行时控制台？`clear` 还是闭集外动词。新名 `editor_remove_output_log` 把通道与「移除」语义补齐。 |

### 1.5 注册期 lint 规则（可机械校验的谓词）

以下是**注册期即判定**的谓词（引擎模块 `tool_registry.cpp`，D38 第二层防御）。不合规 = **注册失败**，构建期就能发现。

| 编号 | 谓词 | 说明 |
|---|---|---|
| L1 | 正则匹配 `^(editor\|running_game\|project\|os)_[a-z0-9_]+$` | 只允许小写字母、数字、下划线；首段必须是一个合法通道 |
| L2 | 剥离通道前缀后的**首个**段 ∈ `convention.verb_closed_set` | 动词位必须是闭集成员 |
| L3 | `channel(name) == 声明 channel` 且 `verb(name) == 声明 verb` | 名字解析结果必须与注册时声明的元数据一致 |
| L4 | `!name.contains("update_")` | 废除 `update_` |
| L5 | 名字不得以名词开头（即 L1+L2 已排除，因为首段是通道、次段是动词） | 名词前缀禁止项 |
| L6 | （**v1.1 修正**）`declared_mutating` **不得由名字的动词段机械推断**，注册期只校验名字与声明的一致性 | v1.0 曾写作「写类动词 ⇒ `mutating=true`」，但 GDR-18 的条件写（`capture_` + 可选 `save_path` 仍会落盘）与 `convert_`/`open_` 两类反例（§6.3）证明该蕴含不成立；`mutating` 已改为**声明字段**，由运行期不变式测试按声明（而非按动词）交叉验证（见 §6） |

**必须给实现者的实现警告——`split('_')[1]` 是错的**：

`running_game_` **自带下划线**，因此「剥离通道前缀」必须按**最长前缀优先**的匹配实现，绝不能用
`name.split('_')[1]` 取动词段。反例：

```
name = "running_game_get_scene_tree"
name.split('_')      -> ["running","game","get","scene","tree"]
name.split('_')[1]   -> "game"        # 错：这不是动词，会误判为「动词位非法」
正确：最长前缀匹配 -> 剥离 "running_game_" -> "get_scene_tree" -> 首段 "get"  # 对
```

正确算法的谓词式：

```python
CHANNELS = ("editor", "running_game", "project", "os")   # 依次尝试，长前缀优先
def parse_tool_name(name):
    for ch in CHANNELS:
        if name.startswith(ch + "_"):
            rest = name[len(ch) + 1:]
            verb, _, tail = rest.partition("_")
            return ch, verb, tail
    raise ValueError("no channel prefix: " + name)
```

对照：`editor_*` 与 `project_*` / `os_*` 只带 1 个下划线，`running_game_` 带 2 个——
**唯一区分方式就是按前缀字符长度降序匹配**。

---

## 2. 174 行完整对照表（映射条目；其中 171 条会真正注册）

列 = `old_name` | `channel` | `verb` | `object` | `new_name` | `mutating` | `scope` | `disposition` | `reason`。
**本节全部表格由脚本 `modules/mcp_server/docs/scripts/gen_table.py` 从 `tool-rename-map.json` 生成并断言 `行数 == 174`**（输出见文末 §7）。
`mutating` 的含义 =「是否改变进程/编辑器/游戏状态**或**产物」（v1.1 共 **103** 条为 true；比 hof-rs `is_mutating` 的「是否修改产物」更宽，
且**禁止**把它直接当作 `MUTATING_EXACT` 使用——口径差异见 §6）。条件写（GDR-18）已经按最保守语义计入 `true`。
`scope` = 工具可被哪些端点使用：`editor` / `game` / `both`（值域见 JSON `convention.scope_enum`）。

### 2.1 `editor_` 通道（@@CNT:editor@@ 条）

@@TABLE:editor@@

### 2.2 `running_game_` 通道（@@CNT:running_game@@ 条）

@@TABLE:running_game@@

### 2.3 `project_` 通道（@@CNT:project@@ 条）

@@TABLE:project@@

### 2.4 `os_` 通道（@@CNT:os@@ 条）

@@TABLE:os@@

**小节合计校验**：@@CHANNELSUM@@

---

## 3. 易混淆分组的消解（用新名说明）

以下 **@@GROUPCOUNT@@** 组覆盖了审计（D34）识别出的**全部**近重名/语义相反/重复实现模式；
每组格式：**旧名如何混淆** → **新名如何一眼区分**。核心手法只有一条：
**把差异从「动词或前后缀」挪到「通道段 + object 段」**——动词保持闭集唯一含义，差异全部显式写进名字。

### 3.0 先看一张「新名重名表」（迁移期必须显式处理的唯一歧义）

以下 **1 个新名对应 2 个旧名**（`disposition = merge_into`，由独立字段 `merge_target` 指向保留方），因此「新名 → 旧名」不是单射；
迁移期做 `is_mutating(old) == is_mutating(new)` 逐项核对时，必须对这两条**显式成对核对**，不能按集合比对。
v1.0 曾计划 3 对合并，其中**两对因有损被 GDR-17 取消**（§4.1b），因此重名组由 3 组降为 **1 组**：

@@MERGEALIAS@@

### 3.1 双进程镜像族（编辑器进程 vs 运行中游戏）

- **旧名如何混淆**：`get_scene_tree` / `get_game_scene_tree`、`get_node_properties` / `get_game_node_properties`、
  `set_node_property` / `set_game_node_property`、`execute_script` 类——差别只有一个 `game` 单词，
  而 `game` 既可能是「游戏进程」，也可能是「编辑器里在编辑的游戏项目」，**作用域完全不可判定**。
- **新名如何一眼区分**：通道段是**第一个词**，且两侧**同一动作同一对象时通道恰好对偶**：
  `editor_get_scene_tree` vs `running_game_get_scene_tree`、
  `editor_get_node_properties` vs `running_game_get_node_properties`、
  `editor_set_node_property` vs `running_game_set_node_property`、
  `editor_execute_gdscript` vs `running_game_execute_gdscript`。
  读到 `editor_` 就知道「只在编辑器进程有效」，读到 `running_game_` 就知道「要经 `user://` 文件 IPC 到达游戏侧」。

### 3.2 文件检索族（文件名 vs 文件内容 vs 引用符号）

- **旧名如何混淆**：`search_files` 只按**文件名**子串匹配（`project.rs:175`），
  `search_in_files` 递归读**文件内容**逐行匹配（`project.rs:194`）；两者只差一个介词 `in_`，
  而智能体在自然语言里几乎不会注意这个介词。第三个 `find_node_references`（`batch.rs:496`）
  同样扫文件内容，只是**聚合口径不同**，v1.0 曾把它并入 `search_in_files`。
- **新名如何一眼区分**：对象段直接写出检索对象——
  `project_search_file_names`（**名字**）vs `project_search_file_contents`（**内容**）；
  第三个则把「找什么」写进 object：**`project_find_files_referencing_symbol`**（按**符号引用**定位文件）。
  三者的差异是**可验证的行为差异**，不是措辞差异：

  | 判别项 | `project_search_file_contents` | `project_find_files_referencing_symbol` |
  |---|---|---|
  | 返回形状 | 逐行 `{file, line, text}` | 按文件聚合 `{file, lines[]}` |
  | 命中上限 | **50** | **100** |
  | 大小写 | **不敏感** | **敏感** |

  三项全部不等价，按 **GDR-17**（合并只在无损时允许）**取消合并**，两者各自保留并各占一个名字；
  迁移期不得再把其中一个当作另一个的别名。

### 3.3 信号五兄弟

| 旧名 | 新名 | 区分点 |
|---|---|---|
| `connect_signal` | `editor_connect_signal` | 建连接（写） |
| `disconnect_signal` | `editor_disconnect_signal` | 断连接（写，**先修实现**：见 §4.3） |
| `get_signals` | `editor_get_node_signals` | 读**某节点**的信号与连接（object 点明 `node_signals`） |
| `analyze_signal_flow` | `editor_analyze_signal_flow` | 遍历**整场景**收集连接与流向，按节点嵌套返回 |
| `find_signal_connections` | `editor_list_signal_connections` | 遍历**整场景**收集**扁平** `connections[]` + `count`，可按 `signal_name` 过滤 |
| `watch_signals` | `running_game_capture_signal_emissions` | **运行中游戏**侧限时监听信号**发射**（不是连接） |

- **旧名如何混淆**：六者都以 `signal(s)` 结尾，`get`/`find`/`watch` 三个动词无法表达
  「读节点局部 / 分析场景全局 / 运行期观测发射」的三层差别；`analyze_signal_flow` 与
  `find_signal_connections` 更是只差一个动词的**近重名**。
- **新名如何一眼区分**：通道先分开（前五条 `editor_`，最后一条 `running_game_`），
  再用动词+object 分开：`connect_`/`disconnect_`（连接）、`get_node_signals`（节点局部读）、
  `analyze_signal_flow`（场景全局分析，嵌套形状）、`list_signal_connections`（场景全局枚举，扁平形状）、
  `capture_signal_emissions`（运行期发射观测）。
- **v1.0 曾把 `find_signal_connections` 并入 `editor_analyze_signal_flow`，v1.1 按 GDR-17 取消**：
  两者实测**四项不等价**（下表），合并即能力丢失，故各自保留：

  | 判别项 | `editor_analyze_signal_flow` | `editor_list_signal_connections` |
  |---|---|---|
  | 返回形状 | 按节点**嵌套** | 扁平 `connections[]` + `count` |
  | 连接筛选 | 仅**持久**连接（`flags & 1`） | 收**全部**连接 |
  | `node_path` 匹配 | **精确** | **子串** |
  | `signal_name` 过滤 | 无 | **有** |

### 3.4 截图 / 帧族

| 旧名 | 新名 | 区分点 |
|---|---|---|
| `get_editor_screenshot` | `editor_capture_screenshot` | 编辑器视口（`EditorInterface.get_base_control`） |
| `get_game_screenshot` | `running_game_capture_screenshot` | 运行中游戏经 `user://mcp_screenshot.png` 文件 IPC 落下的一帧 |
| `capture_frames` | `running_game_capture_frames` | 运行中游戏**连续**抓帧 |
| `compare_screenshots` | `editor_analyze_screenshot_diff` | 编辑器进程内逐像素比较并产出差异图（是 `analyze_`，不是 `capture_`） |

- **旧名如何混淆**：四个都含 `screenshot`/`frame`，`get_` 与 `capture_` 混用，`compare_` 不是闭集动词。
- **新名如何一眼区分**：先通道（`editor_` vs `running_game_`），再动词（`capture_`=取像、
  `analyze_`=分析）。「比较截图」不是取像动作，故**禁止**叫 `*_capture_*`。
- **权限口径（D-1 / GDR-18，v1.1 修正）**：`editor_capture_screenshot` 与 `running_game_capture_screenshot`
  默认只读，但 **`save_path` 非空时会真的把 PNG 写到该路径**（`editor.rs:327-343` / `:395-402`，schema 允许 `res://`）。
  因此两者一律按**条件写**记 `mutating = true`，并在 JSON `reason` 写明触发条件。
  **不要**因为动词是 `capture_` 就把它们判成只读——这正是 §1.5 L6 被修正的原因。

### 3.5 输入族（**这一族是 D27 E3 根因的正面修正**）

| 旧名 | 新名 | 实际作用域 |
|---|---|---|
| `simulate_key` | `editor_simulate_key` | 编辑器进程 `Input` 单例 |
| `simulate_mouse_click` | `editor_simulate_mouse_click` | 编辑器进程 `Input` 单例 |
| `simulate_mouse_move` | `editor_simulate_mouse_move` | 编辑器进程 `Input` 单例 |
| `simulate_action` | `editor_simulate_input_action` | 编辑器进程 `Input` 单例 |
| `simulate_sequence` | `editor_simulate_input_sequence` | 编辑器进程 `Input` 单例 |
| `get_input_actions` | `editor_get_input_actions` | 编辑器进程 `InputMap` 单例（**不读** `project.godot`） |
| `set_input_action` | `editor_add_input_action` | 编辑器进程 `InputMap` 单例 `add_action`（**不落盘**） |
| `click_button_by_text` | `running_game_simulate_button_click_by_text` | **真正**作用于运行中游戏 |

- **旧名如何混淆**：七个 `simulate_*`/`*input_action*` 看起来都在「模拟玩家输入」，
  于是被当成 E3（输入到不了游戏）的修复手段反复使用，其实**一次都没离开编辑器进程**。
  同一个 `set_input_action` 还给人「写项目设置」的错觉。
- **新名如何一眼区分**：`editor_simulate_*` 明确宣告「只注入编辑器进程单例」；
  真正到得了游戏的只有 `running_game_simulate_button_click_by_text`（游戏侧 `emit_signal pressed`
  + 直接调 `_pressed()`）。**唯一**的「写 InputMap」动作是 `add_`（创建型），故 `editor_add_input_action`。
  → 智能体看到 `editor_simulate_*` 就不该再指望它驱动游戏。

### 3.6 `batch_*` 跨进程

| 旧名 | 新名 | 通道 | 区分点 |
|---|---|---|---|
| `batch_get_properties` | `running_game_get_node_properties_batch` | `running_game_` | 经游戏 IPC 批量**读** |
| `batch_set_property` | `editor_set_node_property_batch` | `editor_` | 批量**写编辑场景**同类型节点的同一属性 |
| `batch_add_nodes` | `editor_add_nodes_batch` | `editor_` | 批量加节点 |
| `find_nodes_by_type` | `editor_find_nodes_by_type` | `editor_` | 从编辑场景根递归查找（无 batch 语义） |

- **旧名如何混淆**：`batch_` 是**前缀**（违反「名词前缀」禁止项），挤掉了通道位，
  于是「批量读游戏属性」和「批量写编辑器属性」长得几乎一样，**读/写与两个进程四个维度全部丢失**。
- **新名如何一眼区分**：`batch` 一律降级为 **object 末尾的限定词**（`node_properties_batch` /
  `node_property_batch` / `nodes_batch`），首段让给通道。读者先看到进程，
  再看到动词是 `get_`（读）还是 `set_`/`add_`（写），不会再跨进程误用。

### 3.7 性能重复对

| 旧名 | 新名 | 处置 |
|---|---|---|
| `get_performance_monitors` | `editor_get_performance_monitors` | **保留方** |
| `get_editor_performance` | `editor_get_performance_monitors` | **并入**（`profiling.rs:63` 的返回值是 `:32` 的子集） |

- **旧名如何混淆**：两个名字都含 `performance`，谁更全、该用哪个，**名字完全无法告知**。
- **新名如何一眼区分**：合并后只剩一个名字，歧义**从源头消失**；且 `editor_` 通道明确宣告
  它读的是**编辑器进程 `Performance` 单例**，不是运行中游戏。

### 3.8 `tree` 歧义（scene tree vs AnimationTree）

| 旧名 | 新名 | 指的是哪个 tree |
|---|---|---|
| `get_scene_tree` | `editor_get_scene_tree` | 编辑场景的节点树（scene tree） |
| `get_game_scene_tree` | `running_game_get_scene_tree` | 运行中游戏的节点树（scene tree） |
| `get_filesystem_tree` | `project_get_filesystem_tree` | `res://` 目录树（filesystem tree，不是节点树） |
| `set_tree_parameter` | `editor_set_animation_tree_parameter` | AnimationTree 参数 |
| `get_animation_tree_structure` | `editor_get_animation_tree_structure` | AnimationTree 结构 |

- **旧名如何混淆**：`set_tree_parameter` 里的 `tree` 既可能被读成 scene tree 也可能读成 AnimationTree；
  `get_filesystem_tree` 的 `tree` 又是第三种含义。
- **新名如何一眼区分**：**object 全称化**——`scene_tree` / `filesystem_tree` / `animation_tree_parameter`。
  限定词不再省略，三种 tree 各写全名。

### 3.9 日志三兄弟

| 旧名 | 新名 | 区分点 |
|---|---|---|
| `get_editor_errors` | `editor_get_errors` | 从 `user://logs/godot.log` **过滤 ERROR 行** |
| `get_output_log` | `editor_get_output_log` | 读日志**尾部**并过滤 |
| `clear_output` | `editor_remove_output_log` | 意图**清空**输出（**先修实现**：见 §4.3） |
| `get_test_report` | `editor_get_test_report` | 测试报告（**先修实现**：当前恒返回固定文案） |

- **旧名如何混淆**：`get_editor_errors` 里的 `editor_` 是**形容词前缀**（编辑器错误），
  与规范里的**通道** `editor_` 撞名——读者无法判断它作用在编辑器进程还是「关于编辑器」。
  另外 `clear_output` 有个闭集外动词。
- **新名如何一眼区分**：通道 `editor_` 与对象拆分——`errors`（错误子集）vs `output_log`（日志尾部）
  vs `remove_output_log`（移除）。三者不再共享「editor 前缀」这一层伪装。

### 3.10 导出 / 部署族

| 旧名 | 新名 | 介质 | 处置 |
|---|---|---|---|
| `get_export_info` | `project_get_export_info` | 项目磁盘（`ProjectSettings`） | rename |
| `list_export_presets` | `project_list_export_presets` | 项目磁盘（`res://export_presets.cfg`） | rename |
| `get_android_preset_info` | `project_get_android_preset_info` | 项目磁盘（同上，**不是设备**） | rename |
| `export_project` | `project_export_game` | 项目磁盘（产物落盘） | **unregister_until_implemented** |
| `list_android_devices` | `os_list_android_devices` | 外部进程（`adb devices -l`） | rename |
| `deploy_to_android` | `os_deploy_to_android_device` | 外部进程/设备（`OS.execute` → `godot --export` / `adb install` / `adb shell monkey`） | rename |

- **旧名如何混淆**：六个工具里同时出现 `android`、`export`、`preset`、`deploy`，
  且三个「Android 相关」工具**分属两个通道**（预设信息在磁盘、设备与部署在外部进程），
  只看旧名无法判断哪个需要连接真机、哪个是纯离线读取。
- **新名如何一眼区分**：`project_*` = 只读/写**项目磁盘**，无设备也可用；
  `os_*` = 必须落到**外部进程/设备**（`adb`）。`deploy_` 只在 `os_` 出现，
  `export_` 只在 `project_` 出现，二者不再混同。

### 3.11 赋值动词族（`assign_`/`set_`/`apply_`/`select_`/`clear_`/`attach_`/`update_` → 全部收敛）

| 旧名 | 新名 | 收敛理由 |
|---|---|---|
| `assign_shader_material` | `editor_set_shader_material` | 闭集无 `assign` |
| `apply_particle_preset` | `editor_set_particle_preset` | 闭集无 `apply` |
| `select_nodes` | `editor_set_node_selection` | 闭集无 `select` |
| `attach_script` | `editor_set_node_script` | 闭集无 `attach` |
| `update_property` | `editor_set_node_property` | 废除 `update_` |
| `set_tree_parameter` | `editor_set_animation_tree_parameter` | 保留 `set_`，object 消歧（见 §3.8） |

- **旧名如何混淆**：七个动词（`assign`/`apply`/`select`/`clear`/`attach`/`update`/`set`）表达的是同一类
  「把某值/资源赋到某个位置上」的动作，读者无法从动词判断语义差异，只能逐个查文档；
  而 `clear_`/`select_` 这类还会让人误以为是「非写操作」。
- **新名如何一眼区分**：**单属性赋值一律 `set_`**、**移除语义一律 `remove_`**；差异全部移到 object：
  `shader_material` / `particle_preset` / `node_selection` / `node_script` / `node_property`。
  于是「是不是写操作」可由动词段**机械判定**（这正是 §6 授权判定重做的前提）。

---

## 4. 处置清单（从 JSON `disposition` 聚合）

JSON 的 `disposition` 是**枚举**，取值域为
`rename | keep | merge_into | unregister_until_implemented | fix_implementation_first`
（见 `convention.disposition_enum`；v1.0 的内嵌写法 `merge_into:<old_name>` 已废除，合并目标改由独立字段
**`merge_target`** 指向保留方）。v1.1 的实际聚合为：**@@DISPAGG@@**（脚本输出见 §7）。以下逐条列出全部非 `rename` 项。

### 4.1 `merge_into`（**1 对**——GDR-17 之后唯一维持的合并）

每对都必须**由保留方吸收被合并方的参数**，否则不是「合并」而是**行为回退**。

| 保留方（旧名 → 新名） | 被合并方（旧名 → 新名） | `merge_target` | **代价 / 为什么无损** |
|---|---|---|---|
| `get_performance_monitors` → `editor_get_performance_monitors` | `get_editor_performance` → `editor_get_performance_monitors` | `get_performance_monitors` | 保留方是**超集**（`profiling.rs:32` 已含 `:63` 的全部字段，逐字段核验 8/8 命中），无需吸收新参数。**代价：返回值由平铺改嵌套**——消费者必须按 `get_performance_monitors` 的嵌套形状取值，不能再按被合并方的平铺形状取值。 |

> 按 GDR-17 ②③：维持合并者**必须**在 `reason` 写明形状/字段路径变更；验收证据里必须留下逐字段 diff，
> 否则「子集」可能变成「字段改名导致消费者拿不到值」。v1.1 已把该代价写进 `get_editor_performance` 的 `reason`。

#### 4.1b v1.0 曾计划、v1.1 按 GDR-17 **取消**的两对合并（有损，各自独立保留）

原先 3 对合并中，两对经独立审计实测**不是「重复实现」而是不等价**。用户的诉求是**区分度**而非工具数少，
**名字变长不是约束，能力丢失才是代价**，故两两保留并给可区分的名字（不再有 `merge_target`）：

| v1.0 曾计划的合并 | v1.1 最终处置 | 实测差异（有损，故禁止合并） |
|---|---|---|
| `search_in_files` ⇐ `find_node_references` | `project_search_file_contents` **与** `project_find_files_referencing_symbol` 各自独立 | 输出形状（逐行 `{file,line,text}` vs 按文件聚合 `{file,lines[]}`）、上限 **50 vs 100**、大小写**不敏感 vs 敏感** |
| `analyze_signal_flow` ⇐ `find_signal_connections` | `editor_analyze_signal_flow` **与** `editor_list_signal_connections` 各自独立 | 返回形状（按节点嵌套 vs 扁平 `connections[]`+`count`）、非持久连接过滤（`flags & 1`）、`node_path` **精确 vs 子串**、**`signal_name` 过滤**（后者独有） |

> D41 原先声称「保留方已有扩展名白名单/跳过 addons，故可合并」的说法**指错了**：保留方的扩展名集合是**超集**，
> 且两者都已跳过 `addons/`——真正的差异是上面三项。两对取消合并后，`rename` 项由 162 增至 **164**。
>
> 另：`find_script_references`（`analysis.rs:485`）返回 `content` 与 `files_searched`，与通用内容搜索**契约不同**，
> JSON 明确**保留而不合并**它——不要把这三个工具一起合掉。

### 4.2 `unregister_until_implemented`（2 个）

未实现前**不得注册**（写了名字却做不到 = 谎报能力，比缺功能更贵：智能体会基于假成功继续往下做）。

| 旧名 → 新名 | 为什么当前必须下架（证据位置） |
|---|---|
| `navigate_to` → `running_game_move_player_to_target_via_navigation` | gd 侧 `addons/godot_mcp_rs/mcp_runtime_agent.gd:553-554` 的 `_cmd_navigate_to(_params)` **直接返回错误**：`{"error": "navigate_to 需要项目中配置 NavigationAgent 和导航网格。请在游戏脚本中使用 NavigationAgent2D/3D 实现移动。"}`——即「请自行实现」。工具在 `tools/list` 里可见、调用却永远失败。 |
| `export_project` → `project_export_game` | `godot_mcp_gdext/src/commands/export.rs` 的实现只**校验导出预设**后硬编码返回 `export_started: true`（`export.rs:117` 处 `TODO`），**没有执行任何导出**。 |

**处置要求**：修好前从 `tools/list` 与可调用注册表中**移除**（旧名也不注册），
不得以「保留旧名但不实现」的方式存在；修好后按新名一次性注册，并补齐 B5 批次的三类证据（成功 / 缺参 / 底层失败）。

### 4.3 `fix_implementation_first`（7 个）

以下 7 个**在实现修好前不得以新名注册**。前 2 个是**数据破坏**，优先级最高。

| # | 旧名 → 新名 | 当前为什么算**谎报/破坏** | 证据位置 |
|---|---|---|---|
| 1 | `tilemap_set_cell` → `editor_set_tilemap_cell` | 实现只调 `layer.set_cell(coords)` **单参形式**：`source_id`/`atlas_coords` 全部未生效，**并把既有格子擦掉**，却回报 `set: true`。**这是数据破坏 + 成功谎报**，不是「功能缺失」。 | `tilemap.rs:124` |
| 2 | `tilemap_fill_rect` → `editor_set_tilemap_cells_in_rect` | 同样用单参 `set_cell` **擦除矩形区域内既有格子**，却回报 `filled: N`；实际**未写入任何瓦片**。同样是**数据破坏 + 成功谎报**。 | `tilemap.rs:158` |
| 3 | `bake_navigation_mesh` → `editor_bake_navigation_mesh` | **恒返回 `baked: true`**：`NavigationRegion3D` 只 `set` 一个属性、2D 只赋 `polygon`，从未真正烘焙。 | `navigation.rs:193`（`TODO`） |
| 4 | `get_test_report` → `editor_get_test_report` | 恒返回**固定文案**，未收集任何测试结果——调用者会以为「测试全过」。 | `test.rs:561` |
| 5 | `clear_output` → `editor_remove_output_log` | 只向 stdout 打印空行，**未清空编辑器 Output 面板**。 | `editor.rs:421` |
| 6 | `set_auto_dismiss` → `editor_set_auto_dismiss_dialogs` | 只写一个**无人读取**的 `static`（全仓仅此一处引用），即写了个没人看的变量。 | `editor.rs:618` |
| 7 | `disconnect_signal` → `editor_disconnect_signal` | 忽略 `target_path`，**固定用场景根作 `Callable`** → 断开的可能不是调用者以为的那条连接（静默错连）。 | `node.rs:355` |

> **硬性要求**：`tilemap_set_cell` 与 `tilemap_fill_rect` **必须先写红测试**
> （断言「写入指定 `source_id`/`atlas_coords` 后 `tilemap_get_cell` 返回该值，且区域内其它格子不被擦除」），
> 先看到它**因缺行为而失败**，再改实现；修好前这两个工具不得以新名注册。

**（非规范性补充）实现者另需自证的已知瑕疵**：JSON 的 `reason` 里另外记录了两处「不影响通道名、但实现与名字不符」的
既有事实，实现者改到对应文件时应一并核实，**不得**因为改名而掩盖它们：
`assign_shader_material`（→ `editor_set_shader_material`）的 `reason` 指出实现**忽略 `material_slot`、只会写 `material`**；
`click_button_by_text`（→ `running_game_simulate_button_click_by_text`）的 `reason` 指出 gd 侧是
**发射 `pressed` 信号并直接调 `_pressed()`**，**并非真实输入注入**。
这两项不在 `fix_implementation_first` 之列（故不阻塞改名），但必须在对应批次的三类证据里如实描述。

---

## 5. 迁移与影响面清单

改名是**契约变更**：`tools/list` 的每一个工具名都会被消费方逐字比对。以下逐项给出路径与要改什么。
**只做改名，不改行为**：除 §4 明列的 10 项（**1 merge** / 2 unregister / 7 fix）外，其余 **164 项**是纯重命名；
映射的 174 条中，2 条下架、1 条并入，最终注册 **171** 个工具。

| # | 路径 | 要改什么 |
|---|---|---|
| 1 | `F:\moonbit-hof-rs\tests\fixtures\mcp\tools_list.json` | **契约源**。已按 **GDR-13** 重采为干净 UTF-8（无 BOM、无 U+FFFD、无 Latin-1 残留）：`48749` 字节，sha256 `8f8051c4c0f8941089f0b21a193cef7c51fa7c41d7e312b1463ea8593f313c54`（本次已复核一致）。改名时要**按 JSON 逐项替换 `name`**，并保持 174 条、原顺序不变；描述文本改动会直接触发对等门失败，故除名字外**不动任何字节**。 |
| 2 | `F:\moonbit-hof-rs\src\runtime\policy.rs` | **四张表**：`TESTER_ALLOW_PREFIXES`、`TESTER_ALLOW_EXACT`、`MUTATING_PREFIXES`、`MUTATING_EXACT`（`policy.rs:184-245`）。改为**由 JSON 生成**，并加运行期不变式测试（见 §6）。**禁止**用「给 allow 表加通道前缀」过桥。 |
| 3 | `F:\moonbit-hof-rs\src\adapter\godot.rs` | 工具名字面量与电池步骤名映射。注意其中已有两个**既有通道常量**：`GAME_PROCESS_CHANNEL = "game_process"`、`EDITOR_PROCESS_CHANNEL = "editor_process"`（`godot.rs:2382-2383`）——新名字的通道段应与它们**对齐**（`running_game_` ↔ `game_process`、`editor_` ↔ `editor_process`），不要引入第三套通道命名。 |
| 4 | `F:\moonbit-hof-rs\src\adapter\mod.rs` | 电池（battery）步骤名与工具名绑定处。 |
| 5 | `F:\moonbit-hof-rs\src\prompts\**` | 提示词里对工具的**文字引用**（智能体读到的名字）。 |
| 6 | `F:\moonbit-hof-rs\tests\**` | 断言与用例里出现的旧名；含 `is_mutating`/`is_tester_allowed` 相关测试。 |
| 7 | `F:\RustProjects\godot-mcp-pro\godot_mcp_gdext\src\commands\**` | Rust addon 的 174 个工具定义：**每个改名工具要改两处**——① `ToolDefinition::new("<old_name>", ...)` 的名字参数；② `registry.insert("<old_name>", ...)` 的键。两处必须**原子成对**修改，只改一处会造成「注册了但不可调用」或反过来的静默缺口。（已核对：`commands/**` 下 `ToolDefinition::new` 恰好 **174** 处。） |
| 8 | `F:\RustProjects\godot-mcp-pro\addons\godot_mcp_rs\mcp_runtime_agent.gd` | **只改 MCP 工具名**。该文件里的 `_cmd_*` 分发（如 `"navigate_to": _cmd_navigate_to(params)`，`mcp_runtime_agent.gd:68-70`）与 IPC command 字面量（`"get_scene_tree"`、`"move_to"` 等）属于**内部协议**，hof-rs 不消费它们——**不改内部 IPC command 字面量**，避免改名波及 addon 与引擎模块之间的私有协议。 |
| 9 | `F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\tools\*.cpp` 与 `tool_registry.*` | 引擎模块侧工具注册：① 工具名按 JSON 改名；② **注册期 lint**（L1–L6，§1.5）落进 `tool_registry.cpp`——名字不合规即**注册失败**；③ `tools/*.cpp` 里若引用了旧名（工具间调用/错误信息），一并对齐。 |
| 10 | 引擎侧文档 | `DESIGN-DETAIL.md` §10 的 B1–B5 清单使用**旧名**，改名后需按批次给出「旧名 → 新名」映射；`ACCEPTANCE.md` 的既有记录是**历史证据**，不得回填修改。 |

**执行顺序（承 D34/D38/D45 的落地顺序，范围改为全量）**：
**Phase 0 止血**（零改名，先修 §4.3 的 7 项，其中 2 项 tilemap 先写红测试）
→ **Phase 1 冻结规范 + registry lint 闸门**（本文档 + `tool-rename-map.json` + L1–L6 生效；v1.1 已把
`disposition` 枚举化、补 `merge_target`、按 GDR-17 取消两对有损合并，并按 GDR-18 把两个截图工具记 `mutating=true`）
→ **Phase 2 原子切换**（单提交全绿，含 §6 的运行期不变式测试）
→ **Phase 4 addon 按新名逐个移植**（未移植即不注册）
→ **Phase 5 清理兜底**。

---

## 6. 授权判定重构（**最重要的一节**）

### 6.1 现在的判定是怎么做的

hof-rs 的角色工具矩阵（`src/runtime/policy.rs`，`policy.rs:184-269`）由**四张表**驱动：

```
TESTER_ALLOW_PREFIXES = [get_, list_, read_, search_, find_, analyze_, detect_, simulate_, assert_]   (9)
TESTER_ALLOW_EXACT    = [play_scene, stop_scene, capture_frames, monitor_properties,
                         start_recording, stop_recording, replay_recording, compare_screenshots,
                         run_test_scenario, run_stress_test, get_test_report, wait_for_node,
                         click_button_by_text, navigate_to, move_to, cross_scene_set_property]      (16)
MUTATING_PREFIXES     = [add_, create_, delete_, remove_, set_, update_, edit_]                      (7)
MUTATING_EXACT        = [move_node, rename_node, duplicate_node, attach_script, connect_signal,
                         disconnect_signal, tilemap_set_cell, tilemap_fill_rect, tilemap_clear,
                         batch_set_property, cross_scene_set_property, export_project,
                         execute_editor_script, execute_game_script, reload_plugin, reload_project,
                         set_game_node_property, set_project_setting, set_input_action,
                         bake_navigation_mesh, clear_output, clear_editor_selection]               (22)
```

判定逻辑（`is_mutating` / `is_tester_allowed` / `tool_allowed`，`policy.rs:247-269`）：

```
is_mutating(tool)      = MUTATING_EXACT.contains(tool) || MUTATING_PREFIXES.any(tool.starts_with(p))
is_tester_allowed(tool)= TESTER_ALLOW_EXACT.contains(tool) || TESTER_ALLOW_PREFIXES.any(tool.starts_with(p))

tool_allowed(Tester, tool) =
     NOT is_mutating(tool)
 AND is_tester_allowed(tool)

即  Tester 权限 = (TESTER_ALLOW_PREFIXES ∪ TESTER_ALLOW_EXACT) − (MUTATING_PREFIXES ∪ MUTATING_EXACT)
```

**两张表全部靠「名字首段」匹配**——这就是命名规范不是审美问题、而是**安全前提**的原因。

### 6.2 通道前缀让两张表**同时失效**

新名字的首段是 `editor_` / `running_game_` / `project_` / `os_`，而两张表里的**每一个**前缀
（`get_`/`list_`/`read_`/`search_`/`find_`/`analyze_`/`detect_`/`simulate_`/`assert_` 与
`add_`/`create_`/`delete_`/`remove_`/`set_`/`update_`/`edit_`）**都不会再出现在首段**。
后果分两种，**方向相反，必须分清**：

| 情形 | 发生了什么 | 后果 | 严重性 |
|---|---|---|---|
| **① 只更新 mutating 表、不更新 allow 表** | `editor_set_node_property` 既 `starts_with("editor_")` ∉ mutating → `is_mutating=false`；也不 `starts_with("set_")` ∉ allow → `is_tester_allowed=false` → `tool_allowed=false` | Tester 在**几乎所有工具**上被拒 = **锁死（fail-closed）** | **功能故障，不是越权**（安全但不可用） |
| **② 把 `editor_`/`running_game_` 塞进 allow 表，mutating 侧仍按名字前缀猜** | 全部 `editor_*` 都满足 allow；而 `editor_set_*`/`editor_add_*` 不以 `set_`/`add_` 开头 → `is_mutating=false`，且 `MUTATING_EXACT` 里存的是旧名，对新名**全部失配** | Tester 在**大批写工具**上静默获得写权限（含 `editor_set_node_property`、`editor_add_node`、`project_set_setting`…） | **真实越权**（这才是安全漏洞） |

**关键结论**：危险的不是「表过期」，而是**为了让 Tester 能用而打的那个局部补丁**——
**禁止用「给 allow 表加通道前缀」过桥**。一旦这么打，`editor_`/`running_game_` 进 allow 表，
而 mutating 侧没有同步改成「**按 verb 段判定**」，越权立刻成立。

> 补充事实（D41 的纠正，避免误判现状）：**当前不存在 Tester 权限缺口**。
> Tester 实际可调用的旧工具 **80 个**，其中「语义可写」的 15 个（`play_scene`/`stop_scene`/`start_recording`/
> `stop_recording`/`replay_recording`/`click_button_by_text`/`navigate_to`/`move_to`/`simulate_{key,mouse_click,mouse_move,action,sequence}`/
> `run_test_scenario`/`run_stress_test`）**作用于运行中的游戏或编辑器输入状态、不修改产物**，
> 而 `TESTER_ALLOW_EXACT` 的存在正是为了允许它们取证；唯一会写 `.tscn` 的
> `cross_scene_set_property` **已在 `MUTATING_EXACT` 中**被拒。
> 另有口径说明：映射里的 `mutating`（含游戏/编辑器状态，**v1.1 共 103 条 true**）比 `is_mutating`（`policy.rs:280` 文案即
> 「是否修改产物」）**更宽**，两者不一致属**正常**，不是漏判。
> **硬性禁止（D-5）**：不得把 `tool-rename-map.json` 的 `mutating` 字段**直接**灌进 `MUTATING_EXACT`
> ——该字段把 15 个只改运行中游戏/编辑器状态、不改产物的合法取证工具也算成 true，直接灌入会造成
> **fail-closed 回归**（Tester 连取证都被拒）。策略名单必须按「是否改产物」这一谓词单独生成。

### 6.3 正确做法：三层防御**同时**落地

**第一层：JSON 是唯一事实源，策略名单由表生成**

- `tool-rename-map.json` 是唯一源；`TESTER_ALLOW_*` / `MUTATING_*` **不再手工维护**，
  而由脚本从 JSON 的 `mutating` / `channel` / `verb` 字段**生成**（生成物需可复现：同输入同输出，进 git）。
  **但注意（D-5）**：JSON 的 `mutating` 是「状态**或**产物」的宽口径（v1.1 = 103 条 true），
  而 `MUTATING_*` 需要的是「**是否修改产物**」——两者**不是同一谓词**，生成时必须按后者重新判定，
  **禁止**把 JSON 的 `mutating` 直接当作 `MUTATING_EXACT`。
- 新名字下「是否可写」由 **verb 段**判定：写类动词（`add_ create_ delete_ remove_ set_ edit_ rename_ reparent_
  move_ duplicate_ connect_ disconnect_ play_ stop_ run_ execute_ simulate_ export_ deploy_ reload_ rescan_
  bake_ open_ save_ setup_`）⇒ mutating；读类动词（`get_ list_ read_ find_ search_ analyze_ detect_ validate_
  assert_ capture_ evaluate_ convert_`）⇒ 非 mutating。
  **该推断不是处处成立（§1.5 L6 已修正）**：审计实测至少 3 处反例——
  `project_convert_uid_to_path` / `project_convert_path_to_uid` 的 `convert_` 非写，
  `editor_open_scene` 的 `open_` 属写；再加上 GDR-18 的条件写（`editor_capture_screenshot` /
  `running_game_capture_screenshot` 带 `save_path` 时落盘，故记 true）。
  → 需要**对象/scope 感知的豁免表**，不能只靠动词闭集。
- Tester 的**取证白名单**（如 `running_game_assert_*`、`running_game_run_test_scenario`、
  `editor_play_scene`/`editor_stop_scene`、录制三件套）在 JSON 里**逐条显式列举**，
  而不是靠前缀顺带放行——通道前缀不是权限依据。

**第二层：注册期 lint**（§1.5 的 L1–L6，引擎模块 `tool_registry.cpp`）
名字不合规**注册即失败**，把「名字与声明不一致」挡在构建期，而不是留到运行期按前缀猜。

**第三层：运行期不变式测试**（hof-rs，必须是**安全断言**：不得静默通过）

```
∀ tool ∈ 174:
  is_mutating(new_name)      == declared_mutating(tool)
  channel(new_name)          == declared_channel(tool)
迁移期（逐项，与 old_name 成对）:
  is_mutating(old_name)      == is_mutating(new_name)
```

- 第三条是**迁移期断言**，目的是让任何**权限边界变化**都变成测试失败，必须**显式豁免并给出理由**。
- 已知需要显式豁免的项（D34 的最高严重度发现）：`move_node` → `editor_reparent_node`
  会掉出 `MUTATING_EXACT`（`policy.rs:223`）**且不以任何 mutating 前缀开头** → 若不豁免，
  Tester 会静默获得改名权。该项必须**单独列出并附「为什么仍应拒绝」的安全断言**，
  不允许以「整体豁免一整个通道」的方式绕过。
- 成一票否决：任何一条不变式断言被放宽（例如把 `==` 改成「任一命中即可」），验收即 fail。

**同时禁止**：
1. 给 allow 表加通道前缀过桥（§6.2 的情形②）；
2. 保留旧名的**可见别名**（旧名不得 push 进 `tools/list` 的顺序表）——保留别名会与「前缀式授权」叠加出绕过面（D34 第 5 条）；
3. 让 `is_mutating` 继续做「对名字现场猜前缀」——改名后它必须改为**按 verb 段 / 查表**判定。

---

## 7. 生成、断言与自检的真实输出

> 本节内容为**执行证据**（可复现）：脚本位于 `modules/mcp_server/docs/scripts/`（模板 `template.md` 同目录），
> 只读 `tool-rename-map.json`，只写本文件。复跑命令：`python modules/mcp_server/docs/scripts/gen_table.py`。

```
@@EVIDENCE@@
```

### 7.1 一致性与复核说明

- **本表由脚本生成**：`@@SCRIPT@@` 读 `tool-rename-map.json` 渲染第 2 节四张表，并**断言行数 == 174**；
  文件名分组的计数断言 `editor+running_game+project+os == 174` 同时成立。
- **文档里出现的 `new_name` 100% 来自 JSON**：`@@CHECKSCRIPT@@` 从本文件抽取全部形如
  `<channel>_<verb>_...` 的标识符，逐个回查 JSON 的 `new_name` 集合，输出见 §7 的 `CONSISTENCY` 段。
- **数据源 v1.1 已按 D45 修改**：TASK-001 只改了 `tool-rename-map.json` 的数据字段（两个截图工具 `mutating`、
  取消两对有损合并、`disposition` 枚举化 + `merge_target`、`convention` 补值域与口径条款、三处引文修正），
  未改任何引擎源码或行为；本文档头部与 §7 打印的字节数/sha256 即 v1.1 的真实指纹。
- **契约同源**：`docs/tools_list.renamed.json` 由 `scripts/gen_renamed_contract.py` 从同一份映射机械生成
  （v1.1 = **171** 条），是每批对等门的参照物。
- **本文档自身的指纹**：`TOOL-NAMING.md` 每次生成后的真实字节数与 sha256 由脚本打印在执行输出里。
  **本文档不内嵌自身 sha256**——那会造成自指（本文件字节数/摘要依赖写入前后状态），
  任何「内嵌自身摘要」的做法在数学上都无法自证；可验证的做法是**重复运行**：
  脚本每次运行都会重渲染两次并断言两次渲染结果**逐字节相同**（`DETERMINISM` 段，见 §7），
  并以「写入后读回、逐字节相等」收口。
- **未做的事**：没有重新推导任何一项语义（全部读自 JSON 与 D34/D38/D41/D45 原文）；
  没有修改任何引擎源码、测试或 hof-rs 契约源（旧 fixture 只读）；没有安装依赖；没有占用 9877；
  没有触碰运行中的 Godot 进程（PID 36392）；没有 `git push`。
- **本文件的改动方式**：TASK-001 只通过 `docs/scripts/gen_table.py` 重渲染本文件，**没有手工编辑**任何表格或计数
  （模板里已变化的章节——§2 表头口径、§3 易混淆分组、§4 处置清单、§5 迁移清单、§6 授权判定、§7 证据块——
  全部在 `template.md` 内随生成器一并更新）。
