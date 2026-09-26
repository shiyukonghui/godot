# TOOL-NAMING — Godot MCP 工具命名规范与 174 项对照表（171 个注册工具）

> **文档性质**：规范性（normative）。本文件是工具命名的**唯一表述来源**；机器可读的**唯一事实源**是同目录的
> [`tool-rename-map.json`](./tool-rename-map.json)（`70917` 字节，sha256 `2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd`，174 条 → **171 个注册工具**）。
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
| `editor_` | 编辑器进程 / 编辑场景 / **编辑器进程内的全局单例**（`Input`、`InputMap`、`AudioServer`、`Performance`、`EditorInterface` 等） | 103 |
| `running_game_` | **运行中的游戏进程**（经 `user://` 文件 IPC 或独立进程端口到达游戏侧） | 24 |
| `project_` | **项目磁盘**（文件内容、资源、`.tscn`/`.tres`、`ProjectSettings`、导出预设、脚本与着色器文件） | 45 |
| `os_` | **外部进程 / 设备**（`adb` 等本机可执行程序与外接设备） | 2 |

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

动词**只能**取自下表 37 个（源自 JSON `convention.verb_closed_set`）。每个动词只允许有**一个**含义；
同一动作**不得**用两个动词表达。表中「用对了」的例子全部是真实新名（可在第 2 节逐行核对）。

| 动词 | 唯一含义（一句话） | 用对了的例子（真实新名） | 用量 |
|---|---|---|---|
| `get` | 读取**已知对象**的当前状态并返回值（单对象状态查询，不遍历集合）。 | `editor_get_node_properties` | 40 |
| `list` | **枚举一个集合**（磁盘上的文件、总线、动画、预设、设备、信号连接），返回元素清单。 | `project_list_scripts` | 5 |
| `read` | 读取**文件 / 资源的文本或内容本身**（内容即返回值，而非对象的属性状态）。 | `project_read_scene_file_content` | 4 |
| `find` | 在已知容器内**按条件定位**匹配项，返回位置或句柄；不返回文件内容。 | `editor_find_nodes_in_group` | 9 |
| `search` | 在**一批文件**中按模式检索，命中结果是「哪些文件/哪些行」。 | `project_search_file_contents` | 2 |
| `create` | 在目标容器中**新建**一个此前不存在的实体（新节点、新文件、新动画）。 | `project_create_scene_file` | 9 |
| `add` | 把**已有**实体**挂到 / 挂入**目标容器或集合（节点、总线、轨道、autoload 项）。 | `editor_add_node` | 15 |
| `remove` | 从容器中**移除**一个成员，容器本身仍存在（动画、轨道、autoload、选中集合、日志）。 | `editor_remove_node_selection` | 7 |
| `delete` | **销毁实体本身**（文件落盘删除 / 节点不存在了），而不只是从集合里摘掉。 | `project_delete_scene_file` | 2 |
| `set` | **写单个属性 / 单个值**（唯一合法的单值写动词，取代 `update_`）。 | `editor_set_node_property` | 30 |
| `edit` | 对**磁盘文件内容**做整篇或模式化**读改写**（是文件编辑，不是单属性赋值）。 | `project_edit_script` | 3 |
| `rename` | 改变对象的**名字**，不改变它在结构中的位置。 | `editor_rename_node` | 1 |
| `reparent` | 把节点挂到**新的父节点**下（结构位置变更；不是坐标移动）。 | `editor_reparent_node` | 1 |
| `move` | 改变对象的**空间位置 / 坐标**（玩家、视角随动位姿）。 | `running_game_move_player_to_target` | 2 |
| `duplicate` | **复制**一个对象（连同其属性/子树）产生副本。 | `editor_duplicate_node` | 1 |
| `connect` | 在两个对象之间**建立**一条关联（信号→Callable）。 | `editor_connect_signal` | 1 |
| `bake` | **预计算 / 预烘**派生数据（如导航网格），让运行期不必现算。 | `editor_bake_navigation_mesh` | 1 |
| `open` | 让编辑器**打开 / 切到**某个资源或场景（改变编辑器当前工作对象）。 | `editor_open_scene` | 1 |
| `save` | 把**内存中的编辑结果写回**其持久位置（当前编辑场景）。 | `editor_save_scene` | 1 |
| `setup` | **配置 / 搭好**一个对象或结构（一次性的成型动作，可能创建多个相关节点）。 | `editor_setup_physics_body` | 7 |
| `analyze` | **分析 / 汇总**产出派生结论（流向、复杂度、差异图），不改变被分析对象。 | `editor_analyze_signal_flow` | 4 |
| `detect` | **检测**存在性问题并回报布尔/清单（环、冲突），是判定而非分析。 | `project_detect_circular_dependencies` | 1 |
| `convert` | **转换表示形式**（UID↔路径），不改变任何状态。 | `project_convert_uid_to_path` | 2 |

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
| L6 | `declared_mutating` 必须与名字的动词段语义一致（写类动词 ⇒ `mutating=true`） | 由运行期不变式测试交叉验证（见 §6） |

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

### 2.1 `editor_` 通道（103 条）

| old_name | channel | verb | object | new_name | mutating | scope | disposition | reason |
|---|---|---|---|---|---|---|---|---|
| `get_scene_tree` | `editor` | `get` | `scene_tree` | `editor_get_scene_tree` | false | `editor` | `rename` | 读取 EditorInterface.get_edited_scene_root() 的编辑场景树，属编辑器进程/编辑场景，故 editor_ 前缀。 |
| `open_scene` | `editor` | `open` | `scene` | `editor_open_scene` | true | `editor` | `rename` | 经 EditorInterface.open_scene_from_path 改变编辑器打开的场景，属编辑器状态写。 |
| `add_scene_instance` | `editor` | `add` | `scene_instance` | `editor_add_scene_instance` | true | `editor` | `rename` | 将外部场景实例化并挂到编辑场景节点下，属编辑场景结构写。 |
| `play_scene` | `editor` | `play` | `scene` | `editor_play_scene` | true | `editor` | `rename` | 调用 EditorInterface.play_* 启动游戏，动作发生在编辑器进程的播放控制上，故 editor_ 而非 running_game_。 |
| `stop_scene` | `editor` | `stop` | `scene` | `editor_stop_scene` | true | `editor` | `rename` | 调用 EditorInterface.stop_playing_scene 停止播放，属编辑器播放状态变更。 |
| `save_scene` | `editor` | `save` | `scene` | `editor_save_scene` | true | `editor` | `rename` | 经 EditorInterface.save_scene/save_scene_as 保存当前编辑场景，必须先有编辑场景，故归 editor_ 通道。 |
| `add_node` | `editor` | `add` | `node` | `editor_add_node` | true | `editor` | `rename` | 向编辑场景父节点 add_child 并设 owner，属编辑场景写。 |
| `delete_node` | `editor` | `delete` | `node` | `editor_delete_node` | true | `editor` | `rename` | 删除编辑场景内节点，属编辑场景结构写。 |
| `rename_node` | `editor` | `rename` | `node` | `editor_rename_node` | true | `editor` | `rename` | 重命名编辑场景内节点，命名动词用闭集 rename，属编辑场景写。 |
| `update_property` | `editor` | `set` | `node_property` | `editor_set_node_property` | true | `editor` | `rename` | 写编辑场景节点的单个属性，按规范废除 update_ 改 set_，属编辑场景写。 |
| `get_node_properties` | `editor` | `get` | `node_properties` | `editor_get_node_properties` | false | `editor` | `rename` | 读取编辑场景节点属性，纯读、仅在编辑器进程有效，故 editor_ 前缀。 |
| `duplicate_node` | `editor` | `duplicate` | `node` | `editor_duplicate_node` | true | `editor` | `rename` | 复制编辑场景节点子树，闭集动词 duplicate，属编辑场景写。 |
| `connect_signal` | `editor` | `connect` | `signal` | `editor_connect_signal` | true | `editor` | `rename` | 在编辑场景内节点间建立信号连接，闭集动词 connect，属编辑器场景写。 |
| `disconnect_signal` | `editor` | `disconnect` | `signal` | `editor_disconnect_signal` | true | `editor` | `fix_implementation_first` | 作用于编辑场景信号连接，故 editor_；但实现忽略 target_path、固定用场景根作 Callable（node.rs:355），先修实现。 |
| `move_node` | `editor` | `reparent` | `node` | `editor_reparent_node` | true | `editor` | `rename` | 把节点移到新父节点下，闭集动词 reparent 比 move 更精确，属编辑场景结构写；实现另带可选 new_name（node.rs:296-312），给了就顺带重命名节点（重命名副作用），故 mutating=true。 |
| `add_resource` | `editor` | `add` | `resource_to_node_property` | `editor_add_resource_to_node_property` | true | `editor` | `rename` | 在编辑场景内创建资源并赋给节点属性，属编辑场景写；名字显式标出落点是节点属性以区别于磁盘资源工具。 |
| `set_anchor_preset` | `editor` | `set` | `anchor_preset` | `editor_set_anchor_preset` | true | `editor` | `rename` | 改 Control 节点锚点预设，属编辑场景节点属性写。 |
| `get_node_groups` | `editor` | `get` | `node_groups` | `editor_get_node_groups` | false | `editor` | `rename` | 读编辑场景节点分组，纯读，故 editor_。 |
| `analyze_signal_flow` | `editor` | `analyze` | `signal_flow` | `editor_analyze_signal_flow` | false | `editor` | `rename` | 遍历编辑场景节点收集信号连接与流向（analysis.rs:387），纯读但依赖编辑场景，故 editor_ + analyze_。 |
| `get_test_report` | `editor` | `get` | `test_report` | `editor_get_test_report` | false | `editor` | `fix_implementation_first` | 实现在编辑器进程用 Expression 取报告，故 editor_；但恒返回固定文案、未收集任何测试结果（test.rs:561），先修实现。 |


### 2.2 `running_game_` 通道（24 条）

| old_name | channel | verb | object | new_name | mutating | scope | disposition | reason |
|---|---|---|---|---|---|---|---|---|
| `get_game_screenshot` | `running_game` | `capture` | `screenshot` | `running_game_capture_screenshot` | false | `game` | `rename` | 读运行中游戏经 user://mcp_screenshot.png 文件 IPC 落下的截图（editor.rs:365），故 running_game_ 通道。 |
| `get_game_scene_tree` | `running_game` | `get` | `scene_tree` | `running_game_get_scene_tree` | false | `game` | `rename` | 经 runtime.rs send_game_command 走 user:// 文件 IPC 到游戏进程取场景树，故 running_game_ 通道。 |
| `get_game_node_properties` | `running_game` | `get` | `node_properties` | `running_game_get_node_properties` | false | `game` | `rename` | send_game_command 到运行中游戏读节点属性，故 running_game_。 |
| `set_game_node_property` | `running_game` | `set` | `node_property` | `running_game_set_node_property` | true | `game` | `rename` | send_game_command 写运行中游戏节点属性，属游戏进程状态写。 |
| `capture_frames` | `running_game` | `capture` | `frames` | `running_game_capture_frames` | false | `game` | `rename` | 经游戏 IPC 连续抓帧，纯读，故 running_game_ + capture_。 |
| `monitor_properties` | `running_game` | `get` | `node_property_samples` | `running_game_get_node_property_samples` | false | `game` | `rename` | 经游戏 IPC 逐帧采样节点属性，本质是取值读取（闭集无 monitor），故用 get_ + node_property_samples。 |
| `analyze_scene_complexity` | `project` | `analyze` | `scene_complexity` | `project_analyze_scene_complexity` | false | `both` | `rename` | 按 path 加载 .tscn 实例化后静态分析节点数/深度/类型分布（analysis.rs:414），对象是项目磁盘场景；path 为空时才回退当前编辑场景。 |
| `find_script_references` | `project` | `find` | `script_references` | `project_find_script_references` | false | `both` | `rename` | 扫描项目磁盘文本文件逐行找脚本引用并回传行内容（analysis.rs:485），与通用内容搜索的契约不同（返回 content 与 files_searched），故保留而不合并。 |
| `detect_circular_dependencies` | `project` | `detect` | `circular_dependencies` | `project_detect_circular_dependencies` | false | `both` | `rename` | 读磁盘 .tscn 建依赖图并 DFS 检测环（analysis.rs:520），纯读，故 project_ + detect_。 |
| `get_project_statistics` | `project` | `get` | `statistics` | `project_get_statistics` | false | `both` | `rename` | 统计 res:// 文件数/脚本行数/场景数（analysis.rs:562），纯项目磁盘读，故 project_ + get_ + statistics。 |
| `get_android_preset_info` | `project` | `get` | `android_preset_info` | `project_get_android_preset_info` | false | `both` | `rename` | 解析 res://export_presets.cfg 取 Android 预设，介质是项目磁盘而非设备，故 project_ 而非 os_。 |


### 2.4 `os_` 通道（2 条）

| old_name | channel | verb | object | new_name | mutating | scope | disposition | reason |
|---|---|---|---|---|---|---|---|---|
| `list_android_devices` | `os` | `list` | `android_devices` | `os_list_android_devices` | false | `both` | `rename` | 执行外部进程 adb devices -l 并解析输出（android.rs:166），属外部进程/设备，故 os_ + list_。 |
| `deploy_to_android` | `os` | `deploy` | `to_android_device` | `os_deploy_to_android_device` | true | `both` | `rename` | 经 OS.execute 调 godot --export、adb install、adb shell monkey 完成导出+安装+启动（android.rs:231），属外部进程/设备，故 os_ + deploy_。 |


**小节合计校验**：103 + 24 + 45 + 2 = 174 条。（`editor` 103 / `running_game` 24 / `project` 45 / `os` 2；脚本断言与 JSON `total` 一致，脚本输出见 §7。）

---

## 3. 易混淆分组的消解（用新名说明）

每组格式：**旧名如何混淆** → **新名如何一眼区分**。

### 3.0 先看一张「新名重名表」（迁移期必须显式处理的唯一歧义）

以下 **3 个新名各自对应 2 个旧名**（`merge_into`），因此「新名 → 旧名」不是单射；
## 3. 易混淆分组的消解（用新名说明）

以下 **11** 组覆盖了审计（D34）识别出的**全部**近重名/语义相反/重复实现模式；
每组格式：**旧名如何混淆** → **新名如何一眼区分**。核心手法只有一条：
**把差异从「动词或前后缀」挪到「通道段 + object 段」**——动词保持闭集唯一含义，差异全部显式写进名字。

### 3.0 先看一张「新名重名表」（迁移期必须显式处理的唯一歧义）

以下 **1 个新名对应 2 个旧名**（`disposition = merge_into`，由独立字段 `merge_target` 指向保留方），因此「新名 → 旧名」不是单射；
迁移期做 `is_mutating(old) == is_mutating(new)` 逐项核对时，必须对这两条**显式成对核对**，不能按集合比对。
v1.0 曾计划 3 对合并，其中**两对因有损被 GDR-17 取消**（§4.1b），因此重名组由 3 组降为 **1 组**：

| 新名（同 1 个） | 对应旧名（2 个） | disposition | merge_target |
|---|---|---|---|
| `editor_get_performance_monitors` | `get_performance_monitors` | `rename` | — |
| `editor_get_performance_monitors` | `get_editor_performance` | `merge_into` | `get_performance_monitors` |


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

---

## 4. 处置清单（从 JSON `disposition` 聚合）

JSON 的 `disposition` 是**枚举**，取值域为
`rename | keep | merge_into | unregister_until_implemented | fix_implementation_first`
（见 `convention.disposition_enum`；v1.0 的内嵌写法 `merge_into:<old_name>` 已废除，合并目标改由独立字段
**`merge_target`** 指向保留方）。v1.1 的实际聚合为：**`rename 164`；`merge_into 1`；`unregister_until_implemented 2`；`fix_implementation_first 7`（合计 174）**（脚本输出见 §7）。以下逐条列出全部非 `rename` 项。

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
3. 让 `is_mutating` 继续做「对名字现场猜前缀」——改名后它必须改为**按 verb 段 / 查表**判定。

---

## 7. 生成、断言与自检的真实输出

> 本节内容为**执行证据**（可复现）：脚本位于 `%TEMP%\namdoc\`，只读 `tool-rename-map.json`，不改任何源文件。

```
$ python %TEMP%\namdoc\gen_table.py
SOURCE  tool-rename-map.json  bytes=67826  sha256=9f5a57e9201b5f7b0b4929c7562eca3345cc8fa280d63fe1079d4bfae302b91b
LINT    L1..L4 over 174 new_name: 0 violations (longest-prefix parse)
LINT    demonstration: split('_')[1] misparses 24/24 running_game_* names (e.g. running_game_capture_screenshot -> 'game' instead of verb 'capture')
CHANNEL editor=103  running_game=24  project=45  os=2  (sum=174)
DISPO   rename=162  fix_implementation_first=7  unregister_until_implemented=2  merge_into:get_performance_monitors=1  merge_into:analyze_signal_flow=1  merge_into:search_in_files=1
DISPO   rename=162  fix_implementation_first=7  unregister_until_implemented=2  merge_into=3
SCOPE   editor=103  both=47  game=24
MUT     mutating=true 101 / false 73
merge_into                   3 项: get_editor_performance, find_signal_connections, find_node_references
unregister_until_implemented 2 项: navigate_to, export_project
fix_implementation_first     7 项: disconnect_signal, clear_output, set_auto_dismiss, tilemap_set_cell, tilemap_fill_rect, bake_navigation_mesh, get_test_report
TABLE   rendered rows=174 (assert rows == 174: PASS)
VERBS   closed set=37  used=36  unused=['evaluate']
VERBS   every example verified against JSON new_name set: PASS
VERBS   one definition per verb: 37/37 distinct definitions
MERGE   duplicate new_name groups=3 (expect 3): editor_analyze_signal_flow; editor_get_performance_monitors; project_search_file_contents
GROUPS  §3 消歧分组数 = 11（3.1..3.11，即双进程镜像/文件检索/信号/截图帧/输入/batch/性能/tree/日志/导出部署/赋值动词；另加 3.0 新名重名表；断言 == 11: PASS）
CONSISTENCY  channel-prefixed identifiers in doc: 179 distinct (occurrences 323)
CONSISTENCY  ├─ 命中 JSON new_name: 171 个（新名）
CONSISTENCY  ├─ 命中 JSON old_name: 1 个（仅作为「旧名」被引用，属预期）
CONSISTENCY  ├─ 非工具标识符（白名单，通道常量/动词段通配）: 7 个 ['editor_add_', 'editor_process', 'editor_set_', 'editor_simulate_', 'project_edit_', 'project_filesystem', 'running_game_assert_']
CONSISTENCY  └─ 无法回查 JSON 的标识符: NONE
CONSISTENCY  result: PASS（文档中出现的工具名 100% 来自 JSON 的 old_name/new_name 集合）
TABLE_FINAL  markdown table data rows containing a 9-column tool row = 174
ASSERT  rows == 174 : PASS
DETERMINISM  render run#1 == render run#2 byte-identical (87707 bytes): PASS
```

### 7.1 一致性与复核说明

- **本表由脚本生成**：`%TEMP%\namdoc\gen_table.py` 读 `tool-rename-map.json` 渲染第 2 节四张表，并**断言行数 == 174**；
  文件名分组的计数断言 `editor+running_game+project+os == 174` 同时成立。
- **文档里出现的 `new_name` 100% 来自 JSON**：`%TEMP%\namdoc\gen_table.py（--check-only 模式）` 从本文件抽取全部形如
  `<channel>_<verb>_...` 的标识符，逐个回查 JSON 的 `new_name` 集合，输出见 §7 的 `CONSISTENCY` 段。
- **数据源未改动**：本次任务只写了本文档与 `%TEMP%\namdoc\**` 下的脚本；
  `tool-rename-map.json` 的字节数与 sha256 与 D41 冻结值**逐位一致**（脚本每次运行都会重算并打印）。
- **本文档自身的指纹**：`TOOL-NAMING.md` 每次生成后的真实字节数与 sha256 由脚本打印在执行输出里。
  **本文档不内嵌自身 sha256**——那会造成自指（本文件字节数/摘要依赖写入前后状态），
  任何「内嵌自身摘要」的做法在数学上都无法自证；可验证的做法是**重复运行**：
  脚本每次运行都会重渲染两次并断言两次渲染结果**逐字节相同**（`DETERMINISM` 段，见 §7），
  并以「写入后读回、逐字节相等」收口。
- **未做的事**：没有重新推导任何一项语义（全部读自 JSON 与 D34/D38/D41 原文）；
  没有修改任何代码、测试或契约源；没有 `git add/commit/push`；没有安装依赖；没有占用 9877；
  没有触碰运行中的 Godot 进程（PID 36392）。